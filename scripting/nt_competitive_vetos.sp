#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#include <neotokyo>

#pragma newdecls required

#include <nt_competitive_vetos_enum>

#define PLUGIN_VERSION "1.2.4"

#define NEO_MAX_PLAYERS 32
#define MAX_CUSTOM_TEAM_NAME_LEN 64
// Used for catching bugs where team managed to vote an unavailable option.
#define ITEM_DISABLED_STR "null"
// Versioning used for the veto.cfg format changes.
#define VETOS_CFG_VERSION 1

Handle g_hForwardVetoStageUpdate = INVALID_HANDLE;
Handle g_hForwardVetoPick = INVALID_HANDLE;

static char g_sTag[] = "[MAP PICK]";
static char g_sSound_Veto[] = "ui/buttonrollover.wav";
static char g_sSound_Pick[] = "ui/buttonclick.wav";
static char g_sSound_Results[] = "player/CPcaptured.wav";

// Debug flag for doing funky testing stuff. Don't enable for regular use.
//#define DEBUG

// Debug flag to simulate a random fake veto process. Don't enable for regular use.
//#define DEBUG_FAKE_VETOS
#if defined(DEBUG_FAKE_VETOS)
// How long to wait between fake veto stages
#define DEBUG_FAKE_VETOS_TIMER 5.0
#endif

// Debug flag for forcing all the vetos on the Jinrai team side.
// Note that it's expected that this will report incorrect vote results for NSF,
// as you would be voting from Jinrai in their stead.
//#define DEBUG_ALL_VETOS_BY_JINRAI

char _jinrai_veto[PLATFORM_MAX_PATH];
char _nsf_veto[PLATFORM_MAX_PATH];
char _jinrai_pick[PLATFORM_MAX_PATH];
char _nsf_pick[PLATFORM_MAX_PATH];
char _random_pick[PLATFORM_MAX_PATH];

static bool _wants_to_start_veto_jinrai;
static bool _wants_to_start_veto_nsf;

static VetoStage _veto_stage;

static int _first_veto_team;
static char _pending_map_pick_nomination_for_vote[PLATFORM_MAX_PATH];

ConVar g_hCvar_JinraiName = null;
ConVar g_hCvar_NsfName = null;

// Bit of a hack, but since this killer-info-display panel is the most likely
// element to cancel the veto view, temporarily disable it during the veto,
// if it exists on server.
ConVar g_hCvar_KidPrintToPanel = null;
static bool _kid_print_to_panel_default;

public Plugin myinfo = {
    name = "NT Competitive Vetos",
    description = "Helper plugin for doing tournament map picks/vetos.",
    author = "Rain",
    version = PLUGIN_VERSION,
    url = "https://github.com/Rainyan/sourcemod-nt-competitive-vetos"
};

// Native from plugin: nt_competitive.
native bool Competitive_IsLive();

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    // Remember to always confirm whether we've got nt_competitive loaded with
    // CompPluginIsLoaded() before calling this optional native.
    MarkNativeAsOptional("Competitive_IsLive");

    // These names must be guaranteed globally unique.
    // Also note that renaming them may break other plugins relying on these native calls.
    CreateNative("CompetitiveVetos_IsVetoActive", Native_IsVetoActive);
    CreateNative("CompetitiveVetos_GetVetoMapPoolSize", Native_GetVetoMapPoolSize);
    CreateNative("CompetitiveVetos_GetNameOfMapPoolMap", Native_GetNameOfMapPoolMap);
    return APLRes_Success;
}

public void OnPluginStart()
{
    CreateConVar("sm_nt_competitive_vetos_version", PLUGIN_VERSION, "NT Competitive Vetos plugin version.", FCVAR_DONTRECORD);

    RegAdminCmd("sm_forceveto", Cmd_AdminForceVeto, ADMFLAG_GENERIC, "Admin command to select which team should pick first (skips the coin flip).");

    RegAdminCmd("sm_resetveto", Cmd_AdminResetVeto, ADMFLAG_GENERIC, "Admin command to reset a veto in progress.");
    RegAdminCmd("sm_cancelveto", Cmd_AdminResetVeto, ADMFLAG_GENERIC, "Alias for sm_resetveto.");
    RegAdminCmd("sm_clearveto", Cmd_AdminResetVeto, ADMFLAG_GENERIC, "Alias for sm_resetveto.");

#if defined(DEBUG)
    RegAdminCmd("sm_debug_redisplay_veto", Cmd_AdminDebug_ReDisplayVeto, ADMFLAG_GENERIC, "Re-display the veto.");
#endif

#if defined(DEBUG_FAKE_VETOS)
    RegAdminCmd("sm_debug_fake_veto", Cmd_AdminDebug_FakeVeto, ADMFLAG_GENERIC, "Simulate/fake a random veto process.");
#endif

    RegConsoleCmd("sm_veto", Cmd_StartVeto, "Ready the team for map picks/vetos.");
    RegConsoleCmd("sm_unveto", Cmd_CancelVeto, "Unready the team for map picks/vetos.");

    g_hForwardVetoStageUpdate = CreateGlobalForward("OnMapVetoStageUpdate", ET_Ignore, Param_Cell, Param_Cell);
    g_hForwardVetoPick = CreateGlobalForward("OnMapVetoPick", ET_Ignore, Param_Cell, Param_Cell, Param_String);
}

public void OnAllPluginsLoaded()
{
    g_hCvar_JinraiName = FindConVar("sm_competitive_jinrai_name");
    g_hCvar_NsfName = FindConVar("sm_competitive_nsf_name");

    g_hCvar_KidPrintToPanel = FindConVar("kid_printtopanel");
    if (g_hCvar_KidPrintToPanel != null)
    {
        _kid_print_to_panel_default = g_hCvar_KidPrintToPanel.BoolValue;
    }
}

public void OnMapStart()
{
    if (!PrecacheSound(g_sSound_Veto))
    {
        SetFailState("Failed to precache sound: \"%s\"", g_sSound_Veto);
    }
    else if (!PrecacheSound(g_sSound_Pick))
    {
        SetFailState("Failed to precache sound: \"%s\"", g_sSound_Pick);
    }
    else if (!PrecacheSound(g_sSound_Results))
    {
        SetFailState("Failed to precache sound: \"%s\"", g_sSound_Results);
    }

    ClearVeto();
}

public Action Cmd_AdminResetVeto(int client, int argc)
{
    bool veto_was_previously_active = IsVetoActive();
    ClearVeto();

    if (veto_was_previously_active)
    {
        PrintToChatAll("%s Veto has been reset by admin.", g_sTag);
        PrintToConsoleAll("%s Veto has been reset by admin.", g_sTag);
        LogToGame("%s Veto has been reset by admin.", g_sTag);
    }
    else
    {
        ReplyToCommand(client, "%s No veto was active. Will reset veto internals, regardless.", g_sTag);
    }

    return Plugin_Handled;
}

#if defined(DEBUG)
public Action Cmd_AdminDebug_ReDisplayVeto(int client, int argc)
{
    DoVeto();
    return Plugin_Handled;
}
#endif

void ClearVeto()
{
    strcopy(_jinrai_veto, sizeof(_jinrai_veto), "");
    strcopy(_nsf_veto, sizeof(_nsf_veto), "");
    strcopy(_jinrai_pick, sizeof(_jinrai_pick), "");
    strcopy(_nsf_pick, sizeof(_nsf_pick), "");
    strcopy(_random_pick, sizeof(_random_pick), "");
    strcopy(_pending_map_pick_nomination_for_vote, sizeof(_pending_map_pick_nomination_for_vote), "");

    _wants_to_start_veto_jinrai = false;
    _wants_to_start_veto_nsf = false;

    SetVetoStage(VETO_STAGE_INACTIVE);

    _first_veto_team = 0;

    if (g_hCvar_KidPrintToPanel != null)
    {
        g_hCvar_KidPrintToPanel.BoolValue = _kid_print_to_panel_default;
    }
}

public Action Cmd_StartVeto(int client, int argc)
{
    if (client == 0)
    {
        ReplyToCommand(client, "%s This command cannot be executed by the server.", g_sTag);
        return Plugin_Handled;
    }
    else if (IsVetoActive())
    {
        ReplyToCommand(client, "%s Map picks/veto is already active.", g_sTag);
        return Plugin_Handled;
    }

    int team = GetClientTeam(client);

    if (team <= TEAM_SPECTATOR)
    {
        ReplyToCommand(client, "%s Picks can only be initiated by the players.", g_sTag);
        return Plugin_Handled;
    }
    else if (IsPlayingTeamEmpty())
    {
        ReplyToCommand(client, "%s Both teams need to have players in them to start the map picks.", g_sTag);
        return Plugin_Handled;
    }
    // Need to confirm comp plugin is loaded before attempting to call optional native.
    else if (CompPluginIsLoaded() && Competitive_IsLive())
    {
        ReplyToCommand(client, "%s Cannot start the veto when the match is live.", g_sTag);
        return Plugin_Handled;
    }

    char team_name[MAX_CUSTOM_TEAM_NAME_LEN];
    GetCompetitiveTeamName(team, team_name, sizeof(team_name));

    if (team == TEAM_JINRAI)
    {
        if (_wants_to_start_veto_jinrai)
        {
            ReplyToCommand(client, "%s Already ready for veto. Please use !unveto if you wish to cancel.", g_sTag);
            return Plugin_Handled;
        }
        else
        {
            _wants_to_start_veto_jinrai = true;
            PrintToChatAll("%s Team %s is ready to start map picks/veto.", g_sTag, team_name);
        }
    }
    else
    {
        if (_wants_to_start_veto_nsf)
        {
            ReplyToCommand(client, "%s Already ready for veto. Please use !unveto if you wish to cancel.", g_sTag);
            return Plugin_Handled;
        }
        else
        {
            _wants_to_start_veto_nsf = true;
            PrintToChatAll("%s Team %s is ready to start map picks/veto.", g_sTag, team_name);
        }
    }

    if (!CheckIfReadyToStartVeto())
    {
        char other_team_name[MAX_CUSTOM_TEAM_NAME_LEN];
        GetCompetitiveTeamName(GetOpposingTeam(team), other_team_name, sizeof(other_team_name));

        PrintToChatAll("%s Waiting for team %s to confirm with !veto.", g_sTag, other_team_name);
    }

    return Plugin_Handled;
}

public Action Cmd_CancelVeto(int client, int argc)
{
    if (client == 0)
    {
        ReplyToCommand(client, "%s This command cannot be executed by the server.", g_sTag);
        return Plugin_Handled;
    }
    else if (IsVetoActive())
    {
        ReplyToCommand(client, "%s Map picks/veto is already active.", g_sTag);
        return Plugin_Handled;
    }

    int team = GetClientTeam(client);

    if (team <= TEAM_SPECTATOR)
    {
        ReplyToCommand(client, "%s Picks can only be uninitiated by the players.", g_sTag);
        return Plugin_Handled;
    }
    // Need to confirm comp plugin is loaded before attempting to call optional native.
    else if (CompPluginIsLoaded() && Competitive_IsLive())
    {
        ReplyToCommand(client, "%s Match is already live; cannot modify a veto right now.", g_sTag);
        return Plugin_Handled;
    }

    char team_name[MAX_CUSTOM_TEAM_NAME_LEN];
    GetCompetitiveTeamName(team, team_name, sizeof(team_name));

    if (team == TEAM_JINRAI)
    {
        if (!_wants_to_start_veto_jinrai)
        {
            ReplyToCommand(client, "%s Already not ready for veto. Please use !veto if you wish to start a veto.", g_sTag);
            return Plugin_Handled;
        }
        else
        {
            _wants_to_start_veto_jinrai = false;
            PrintToChatAll("%s Team %s is no longer ready for !veto.", g_sTag, team_name);
        }
    }
    else
    {
        if (!_wants_to_start_veto_nsf)
        {
            ReplyToCommand(client, "%s Already not ready for veto. Please use !veto if you wish to start a veto.", g_sTag);
            return Plugin_Handled;
        }
        else
        {
            _wants_to_start_veto_nsf = false;
            PrintToChatAll("%s Team %s is no longer ready for !veto.", g_sTag, team_name);
        }
    }

    return Plugin_Handled;
}

public Action Cmd_AdminForceVeto(int client, int argc)
{
    if (IsVetoActive())
    {
        ReplyToCommand(client, "%s Picks already active. Use !resetveto first.", g_sTag);
        return Plugin_Handled;
    }
    else if (IsPlayingTeamEmpty())
    {
        ReplyToCommand(client, "%s Both teams need to have players in them to start the map picks.", g_sTag);
        return Plugin_Handled;
    }

    char cmd_name[32];
    GetCmdArg(0, cmd_name, sizeof(cmd_name));

    if (argc != 1)
    {
        ReplyToCommand(client, "%s Usage: %s jinrai/nsf (don't use a team custom name)", g_sTag, cmd_name);
        return Plugin_Handled;
    }
    // Need to confirm comp plugin is loaded before attempting to call optional native.
    else if (CompPluginIsLoaded() && Competitive_IsLive())
    {
        ReplyToCommand(client, "%s Cannot start the veto when the match is live.", g_sTag);
        return Plugin_Handled;
    }

    char team_name[7]; // "Jinrai" + '\0'
    GetCmdArg(1, team_name, sizeof(team_name));
    int team_that_goes_first;
    if (StrEqual(team_name, "Jinrai", false))
    {
        team_that_goes_first = TEAM_JINRAI;
    }
    else if (StrEqual(team_name, "NSF", false))
    {
        team_that_goes_first = TEAM_NSF;
    }

    if (team_that_goes_first != TEAM_JINRAI && team_that_goes_first != TEAM_NSF)
    {
        ReplyToCommand(client, "%s Usage: %s jinrai/nsf", g_sTag, cmd_name);
        return Plugin_Handled;
    }

    _wants_to_start_veto_jinrai = true;
    _wants_to_start_veto_nsf = true;
    StartNewVeto(team_that_goes_first);

    PrintToChatAll("%s Veto has been manually started by admin (team %s goes first).",
        g_sTag,
        (team_that_goes_first == TEAM_JINRAI) ? "Jinrai" : "NSF"); // Not reusing team_name to ensure Nice Capitalization.

    return Plugin_Handled;
}

bool CheckIfReadyToStartVeto()
{
    if (IsVetoActive() || !_wants_to_start_veto_jinrai || !_wants_to_start_veto_nsf)
    {
        return false;
    }
    StartNewVeto();
    return true;
}

void StartNewVeto(int team_goes_first = 0)
{
    if (IsVetoActive())
    {
        ThrowError("Called while another veto is already active");
    }
    else if (ResetPicksIfShould())
    {
        return;
    }

    ClearVeto();

    PrintToChatAll("%s Starting map picks/veto...", g_sTag);
    EmitSoundToAll(g_sSound_Results);

    if (team_goes_first == 0)
    {
        DoCoinFlip();
    }
    else
    {
        _first_veto_team = team_goes_first;
        CreateTimer(0.1, Timer_StartVeto, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

void DoCoinFlip(const int coinflip_stage = 0)
{
    if (ResetPicksIfShould())
    {
        return;
    }

    SetVetoStage(VETO_STAGE_COIN_FLIP);

    Panel panel = new Panel();
    panel.SetTitle(g_sTag);

    // Characters to represent the "coin flip" spinning around, for some appropriate suspense.
    char coinflip_anim[][] = { "-", "\\", "|", "/" };
    // How many 180 coin flips for the full animation, ie. 3 = 1.5 full rotations.
#define NUM_COINFLIP_ANIMATION_HALF_ROTATIONS 3

    if (coinflip_stage < sizeof(coinflip_anim) * NUM_COINFLIP_ANIMATION_HALF_ROTATIONS)
    {
        char text[19];
        Format(text, sizeof(text), "Flipping coin... %s", coinflip_anim[coinflip_stage % sizeof(coinflip_anim)]);
        panel.DrawText(" ");
        panel.DrawText(text);

        CreateTimer(0.33, Timer_CoinFlip, coinflip_stage + 1, TIMER_FLAG_NO_MAPCHANGE);
    }
    else
    {
#if defined DEBUG_ALL_VETOS_BY_JINRAI
        _first_veto_team = TEAM_JINRAI;
#else
        SetRandomSeed(GetTime());
        _first_veto_team = GetRandomInt(TEAM_JINRAI, TEAM_NSF);
#endif
        char team_name[MAX_CUSTOM_TEAM_NAME_LEN];
        GetCompetitiveTeamName(_first_veto_team, team_name, sizeof(team_name));

        char text[20 + MAX_CUSTOM_TEAM_NAME_LEN];
        // Still adding the "Flipping coin..." part here for visual continuity from the coin flipping stage.
        Format(text, sizeof(text), "Flipping coin... Team %s vetoes first.", team_name);

        panel.DrawText(" ");
        panel.DrawText(text);

        PrintToConsoleAll("%s %s", g_sTag, text);
        LogToGame("%s %s", g_sTag, text);

        SetVetoStage(VETO_STAGE_COIN_FLIP_RESULT);

#define COINFLIP_RESULTS_SHOW_DURATION 5
        CreateTimer(float(COINFLIP_RESULTS_SHOW_DURATION), Timer_StartVeto, _, TIMER_FLAG_NO_MAPCHANGE);
    }

    for (int client = 1; client <= MaxClients; ++client)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
        {
            continue;
        }
        panel.Send(client, MenuHandler_DoNothing, COINFLIP_RESULTS_SHOW_DURATION);
    }
    delete panel;
}

public Action Timer_StartVeto(Handle timer)
{
    if (ResetPicksIfShould())
    {
        return Plugin_Stop;
    }
    DoVeto();
    return Plugin_Stop;
}

void DoVeto()
{
    if (!IsVetoActive())
    {
        ThrowError("Called DoVeto while !IsVetoActive");
    }

    if (GetVetoStage() >= NUM_STAGES)
    {
        ThrowError("Invalid veto stage (%d)", _veto_stage);
    }
    else if (GetVetoStage() == VETO_STAGE_COIN_FLIP_RESULT)
    {
        SetVetoStage(VETO_STAGE_FIRST_TEAM_BAN);

        if (g_hCvar_KidPrintToPanel != null)
        {
            _kid_print_to_panel_default = g_hCvar_KidPrintToPanel.BoolValue;
            g_hCvar_KidPrintToPanel.BoolValue = false;
        }
    }

    if (ResetPicksIfShould())
    {
        return;
    }

    if (strlen(_pending_map_pick_nomination_for_vote) != 0)
    {
        LogError("_pending_map_pick_nomination_for_vote not empty");
        return;
    }

    int picking_team = GetPickingTeam();
#if defined DEBUG_ALL_VETOS_BY_JINRAI
    picking_team = TEAM_JINRAI;
#endif

    DataPack dp_maps = new DataPack();
    bool all_maps_exist_on_server;
    int veto_pool_size = GetMaps(dp_maps, all_maps_exist_on_server);
    if (veto_pool_size == -1)
    {
        delete dp_maps;
        ThrowError("Failed to get maps");
    }
    else if (veto_pool_size < 5)
    {
        delete dp_maps;
        ThrowError("Need at least 5 maps on veto pool (got %d)", veto_pool_size);
    }
    else if (!all_maps_exist_on_server &&
        GetVetoStage() == VETO_STAGE_FIRST_TEAM_BAN)
    {
        PrintToChatAll("%s Warning: the veto map pool contains map(s) that \
don't exist on this server!", g_sTag);
    }

    if (GetVetoStage() == VETO_STAGE_RANDOM_THIRD_MAP)
    {
        dp_maps.Reset();
        DataPack dp_unchosen_maps = new DataPack();
        int num_remaining_maps;
        char map_name_buffer[PLATFORM_MAX_PATH];
        for (int i = 0; i < veto_pool_size; ++i)
        {
            dp_maps.ReadString(map_name_buffer, sizeof(map_name_buffer));
            if (StrEqual(map_name_buffer, _jinrai_veto) ||
                StrEqual(map_name_buffer, _nsf_veto) ||
                StrEqual(map_name_buffer, _jinrai_pick) ||
                StrEqual(map_name_buffer, _nsf_pick))
            {
                continue;
            }
            dp_unchosen_maps.WriteString(map_name_buffer);
            ++num_remaining_maps;
        }
        if (num_remaining_maps == 0)
        {
            delete dp_maps;
            delete dp_unchosen_maps;
            ThrowError("No maps left to choose from");
        }

        SetRandomSeed(GetTime());
        int third_map_index = GetRandomInt(0, num_remaining_maps - 1);

        dp_unchosen_maps.Reset();
        for (int i = 0; i < third_map_index; ++i)
        {
            dp_unchosen_maps.ReadString(map_name_buffer, sizeof(map_name_buffer));
        }
        dp_unchosen_maps.ReadString(map_name_buffer, sizeof(map_name_buffer));
        delete dp_unchosen_maps;
        delete dp_maps;

        SetMapVetoPick(TEAM_SPECTATOR, map_name_buffer);
        AnnounceMaps();

        ClearVeto();
        return;
    }

    if (picking_team != TEAM_JINRAI && picking_team != TEAM_NSF)
    {
        delete dp_maps;
        ThrowError("Invalid picking team: %d", picking_team);
    }

    Menu picker_menu = new Menu(MenuHandler_DoPick, (MenuAction_Select | MenuAction_End));
    picker_menu.ExitButton = false;

    Panel spec_panel = new Panel();
    spec_panel.SetTitle(g_sTag);
    spec_panel.DrawText(" ");

    char jinrai_name[MAX_CUSTOM_TEAM_NAME_LEN];
    char nsf_name[MAX_CUSTOM_TEAM_NAME_LEN];
    GetCompetitiveTeamName(TEAM_JINRAI, jinrai_name, sizeof(jinrai_name));
    GetCompetitiveTeamName(TEAM_NSF, nsf_name, sizeof(nsf_name));

    bool is_ban_stage = (GetVetoStage() == VETO_STAGE_FIRST_TEAM_BAN ||
        GetVetoStage() == VETO_STAGE_SECOND_TEAM_BAN);

    picker_menu.SetTitle("Your team's map %s:", is_ban_stage ? "VETO" : "PICK");
    picker_menu.Pagination = Min(veto_pool_size, 7);

    spec_panel.DrawText(is_ban_stage ? "Waiting for veto by:" : "Waiting for pick by:");
    spec_panel.DrawText((picking_team == TEAM_JINRAI) ? jinrai_name : nsf_name);
    spec_panel.DrawText(" ");

    char map_name_buffer[PLATFORM_MAX_PATH];
    char buffer[PLATFORM_MAX_PATH + MAX_CUSTOM_TEAM_NAME_LEN + 11 + 1];
    dp_maps.Reset();
    for (int i = 0; i < veto_pool_size; ++i)
    {
        dp_maps.ReadString(map_name_buffer, sizeof(map_name_buffer));

        if (StrEqual(map_name_buffer, _jinrai_veto))
        {
            Format(buffer, sizeof(buffer), "%s (VETO of %s)", map_name_buffer, jinrai_name);
            picker_menu.AddItem(ITEM_DISABLED_STR, buffer, ITEMDRAW_DISABLED);
            spec_panel.DrawText(buffer);
        }
        else if (StrEqual(map_name_buffer, _nsf_veto))
        {
            Format(buffer, sizeof(buffer), "%s (VETO of %s)", map_name_buffer, nsf_name);
            picker_menu.AddItem(ITEM_DISABLED_STR, buffer, ITEMDRAW_DISABLED);
            spec_panel.DrawText(buffer);
        }
        else if (StrEqual(map_name_buffer, _jinrai_pick))
        {
            Format(buffer, sizeof(buffer), "%s (PICK of %s)", map_name_buffer, jinrai_name);
            picker_menu.AddItem(ITEM_DISABLED_STR, buffer, ITEMDRAW_DISABLED);
            spec_panel.DrawText(buffer);
        }
        else if (StrEqual(map_name_buffer, _nsf_pick))
        {
            Format(buffer, sizeof(buffer), "%s (PICK of %s)", map_name_buffer, nsf_name);
            picker_menu.AddItem(ITEM_DISABLED_STR, buffer, ITEMDRAW_DISABLED);
            spec_panel.DrawText(buffer);
        }
        else
        {
            picker_menu.AddItem(map_name_buffer, map_name_buffer, ITEMDRAW_DEFAULT);
            spec_panel.DrawText(map_name_buffer);
        }
    }
    delete dp_maps;

    int num_picker_menu_users;
    for (int client = 1; client <= MaxClients; ++client)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
        {
            continue;
        }

        if (GetClientTeam(client) == picking_team)
        {
            picker_menu.Display(client, MENU_TIME_FOREVER);
            ++num_picker_menu_users;
        }
        else
        {
            spec_panel.Send(client, MenuHandler_DoNothing, MENU_TIME_FOREVER);
        }
    }
    if (num_picker_menu_users == 0)
    {
        delete picker_menu;
    }
    delete spec_panel;
}

public Action Timer_CoinFlip(Handle timer, int coinflip_stage)
{
    if (IsVetoActive() && !ResetPicksIfShould())
    {
        DoCoinFlip(coinflip_stage);
    }
    return Plugin_Stop;
}

public int MenuHandler_DoNothing(Menu menu, MenuAction action, int param1, int param2)
{
}

// Note that the callback params are guaranteed to actually represent client & selection
// only in some MenuActions. We are only subscribing to MenuAction_End and MenuAction_Select,
// so this is a safe assumption here.
public int MenuHandler_DoPick(Menu menu, MenuAction action, int client, int selection)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }
    // Else, (action == MenuAction_Select), because those are the only two actions we receive here

    bool veto_was_cancelled = ResetPicksIfShould();

    if (!veto_was_cancelled && client > 0 && client <= MaxClients &&
        IsClientInGame(client) && !IsFakeClient(client))
    {
        int client_team = GetClientTeam(client);
        if (client_team == GetPickingTeam())
        {
            char jinrai_name[MAX_CUSTOM_TEAM_NAME_LEN];
            char nsf_name[MAX_CUSTOM_TEAM_NAME_LEN];
            GetCompetitiveTeamName(TEAM_JINRAI, jinrai_name, sizeof(jinrai_name));
            GetCompetitiveTeamName(TEAM_NSF, nsf_name, sizeof(nsf_name));

            char chosen_map[PLATFORM_MAX_PATH];
            if (!menu.GetItem(selection, chosen_map, sizeof(chosen_map)))
            {
                ThrowError("GetItem failed");
                return 0;
            }
            else if (StrEqual(chosen_map, ITEM_DISABLED_STR))
            {
                ThrowError("Client chose disabled str from menu (%d)", selection);
            }

            ConfirmSoloMapPick(client, client_team, chosen_map);
        }
    }
    menu.Cancel();
    return 0;
}

void ConfirmSoloMapPick(int client, int team, const char[] map_name)
{
    if (team != TEAM_JINRAI && team != TEAM_NSF)
    {
        ThrowError("Unexpected team: %d", team);
    }
    else if (strlen(map_name) == 0)
    {
        ThrowError("Empty map name");
    }

    strcopy(_pending_map_pick_nomination_for_vote,
        sizeof(_pending_map_pick_nomination_for_vote), map_name);

    Menu vote_menu = new Menu(MenuHandler_ConfirmSoloMapPick, MenuAction_End);
    vote_menu.ExitButton = false;
    vote_menu.VoteResultCallback = VoteHandler_ConfirmSoloMapPick;

    bool is_ban_stage = (GetVetoStage() == VETO_STAGE_FIRST_TEAM_BAN ||
        GetVetoStage() == VETO_STAGE_SECOND_TEAM_BAN);

    vote_menu.SetTitle("Team %s suggestion by %N: %s (need at least 50%c consensus)",
        is_ban_stage ? "VETO" : "PICK",
        client,
        map_name,
        '%'); // Note: the panel formats text differently, so need to use %c -> '%' for percentages here.

    vote_menu.AddItem("yes", "Vote yes", ITEMDRAW_DEFAULT);
    vote_menu.AddItem("no", "Vote no", ITEMDRAW_DEFAULT);

    int voters[NEO_MAX_PLAYERS];
    int num_voters;
    for (int iter_client = 1; iter_client <= MaxClients; ++iter_client)
    {
        if (!IsClientInGame(iter_client) || IsFakeClient(iter_client))
        {
            continue;
        }
        if (GetClientTeam(iter_client) != team)
        {
            continue;
        }
        voters[num_voters++] = iter_client;
    }

    if (IsVoteInProgress())
    {
        CancelVote();
        PrintToChatAll("%s Cancelling existing vote because veto voting is currently active.", g_sTag);
    }
    vote_menu.DisplayVote(voters, num_voters, MENU_TIME_FOREVER);
}

public int MenuHandler_ConfirmSoloMapPick(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
}

public void VoteHandler_ConfirmSoloMapPick(Menu menu, int num_votes, int num_clients,
    const int[][] client_info, int num_items, const int[][] item_info)
{
    // Vote has been reset by this plugin (admin reset, etc.)
    if (!IsVetoActive())
    {
        return;
    }

    // Nobody voted yes/no, don't do anything yet.
    if (num_votes == 0)
    {
        strcopy(_pending_map_pick_nomination_for_vote,
            sizeof(_pending_map_pick_nomination_for_vote), "");
        return;
    }

    int num_yes_votes;
    int num_no_votes;
    int voting_team;

    for (int i = 0; i < num_clients; ++i)
    {
        if (voting_team == 0)
        {
            voting_team = GetClientTeam(client_info[i][0]);
            if (voting_team != TEAM_JINRAI && voting_team != TEAM_NSF)
            {
                ThrowError("Failed to get a valid voting team (%d)", voting_team);
            }
        }

        if (client_info[i][1] == 0)
        {
            ++num_yes_votes;
        }
        else
        {
            ++num_no_votes;
        }
    }

    if (num_yes_votes >= num_no_votes)
    {
        char jinrai_name[MAX_CUSTOM_TEAM_NAME_LEN];
        char nsf_name[MAX_CUSTOM_TEAM_NAME_LEN];
        GetCompetitiveTeamName(TEAM_JINRAI, jinrai_name, sizeof(jinrai_name));
        GetCompetitiveTeamName(TEAM_NSF, nsf_name, sizeof(nsf_name));

        if (GetVetoStage() == VETO_STAGE_FIRST_TEAM_BAN || GetVetoStage() == VETO_STAGE_SECOND_TEAM_BAN)
        {
            SetMapVetoPick(voting_team, _pending_map_pick_nomination_for_vote);
            EmitSoundToAll(g_sSound_Veto);

            PrintToAllExceptTeam(voting_team, "[VETO] Team %s vetoes map: %s",
                (voting_team == TEAM_JINRAI) ? jinrai_name : nsf_name,
                _pending_map_pick_nomination_for_vote);
            LogToGame("[VETO] Team %s vetoes map: %s",
                (voting_team == TEAM_JINRAI) ? jinrai_name : nsf_name,
                _pending_map_pick_nomination_for_vote);
        }
        else if (GetVetoStage() == VETO_STAGE_FIRST_TEAM_PICK || GetVetoStage() == VETO_STAGE_SECOND_TEAM_PICK)
        {
            SetMapVetoPick(voting_team, _pending_map_pick_nomination_for_vote);
            EmitSoundToAll(g_sSound_Pick);

            PrintToAllExceptTeam(voting_team, "[PICK] Team %s picks map: %s",
                (voting_team == TEAM_JINRAI) ? jinrai_name : nsf_name,
                _pending_map_pick_nomination_for_vote);
            LogToGame("[PICK] Team %s picks map: %s",
                (voting_team == TEAM_JINRAI) ? jinrai_name : nsf_name,
                _pending_map_pick_nomination_for_vote);
        }
        else
        {
            ThrowError("Unexpected veto stage: %d", GetVetoStage());
        }

        PrintToTeam(voting_team, "%s Your team %sed map %s (%d%s \"yes\" votes of %d votes total).",
            (GetVetoStage() == VETO_STAGE_FIRST_TEAM_BAN || GetVetoStage() == VETO_STAGE_SECOND_TEAM_BAN) ? "[VETO]" : "[PICK]",
            (GetVetoStage() == VETO_STAGE_FIRST_TEAM_BAN || GetVetoStage() == VETO_STAGE_SECOND_TEAM_BAN) ? "veto" : "pick",
            _pending_map_pick_nomination_for_vote,
            (num_yes_votes == 0) ? 100 : ((1 - (num_no_votes / num_yes_votes)) * 100),
            "%%",
            num_votes);

        SetVetoStage(view_as<VetoStage>(view_as<int>(GetVetoStage()) + 1));
    }
    else
    {
        PrintToTeam(voting_team, "%s Need at least 50%s of \"yes\" votes (got %d%s).",
            g_sTag,
            "%%",
            (num_no_votes == 0) ? 0 : (num_yes_votes / num_no_votes),
            "%%");
    }

    strcopy(_pending_map_pick_nomination_for_vote,
        sizeof(_pending_map_pick_nomination_for_vote), "");

    if (IsVetoActive())
    {
        DoVeto();
    }
}

stock int GetOpposingTeam(int team)
{
#if defined DEBUG_ALL_VETOS_BY_JINRAI
    return TEAM_JINRAI;
#else
    return (team == TEAM_JINRAI) ? TEAM_NSF : TEAM_JINRAI;
#endif
}

int GetPickingTeam()
{
    if (GetVetoStage() == VETO_STAGE_FIRST_TEAM_BAN || GetVetoStage() == VETO_STAGE_FIRST_TEAM_PICK)
    {
        return _first_veto_team;
    }
    if (GetVetoStage() == VETO_STAGE_SECOND_TEAM_BAN || GetVetoStage() == VETO_STAGE_SECOND_TEAM_PICK)
    {
        return GetOpposingTeam(_first_veto_team);
    }
    return 0;
}

bool ResetPicksIfShould()
{
    // Need to confirm comp plugin is loaded before attempting to call optional native.
    if (CompPluginIsLoaded() && Competitive_IsLive())
    {
        PrintToChatAll("%s Game is already live, cancelling pending map picks.", g_sTag);
        PrintToConsoleAll("%s Game is already live, cancelling pending map picks.", g_sTag);
        LogToGame("%s Game is already live, cancelling pending map picks.", g_sTag);
        ClearVeto();
        return true;
    }
    if (IsPlayingTeamEmpty())
    {
        PrintToChatAll("%s Team is empty, cancelling map picks.", g_sTag);
        PrintToConsoleAll("%s Team is empty, cancelling map picks.", g_sTag);
        LogToGame("%s Team is empty, cancelling map picks.", g_sTag);
        ClearVeto();
        return true;
    }
    return false;
}

bool IsPlayingTeamEmpty()
{
#if defined DEBUG_ALL_VETOS_BY_JINRAI
    return GetNumPlayersInTeam(TEAM_JINRAI) == 0;
#else
    return GetNumPlayersInTeam(TEAM_JINRAI) == 0 || GetNumPlayersInTeam(TEAM_NSF) == 0;
#endif
}

int GetNumPlayersInTeam(int team)
{
    int num_players = 0;
    for (int client = 1; client <= MaxClients; ++client)
    {
        if (!IsClientInGame(client))
        {
            continue;
        }
        if (GetClientTeam(client) == team)
        {
            ++num_players;
        }
    }
    return num_players;
}

void PrintToTeam(int team, const char[] message, any ...)
{
    if (team < TEAM_NONE || team > TEAM_NSF)
    {
        ThrowError("Invalid team: %d", team);
    }

    char formatMsg[512];
    VFormat(formatMsg, sizeof(formatMsg), message, 3);

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
        {
            continue;
        }
        if (GetClientTeam(client) != team)
        {
            continue;
        }
        PrintToChat(client, formatMsg);
        PrintToConsole(client, formatMsg);
    }
}

void PrintToAllExceptTeam(int team, const char[] message, any ...)
{
    if (team < TEAM_NONE || team > TEAM_NSF)
    {
        ThrowError("Invalid team: %d", team);
    }

    char formatMsg[512];
    VFormat(formatMsg, sizeof(formatMsg), message, 3);

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
        {
            continue;
        }
        if (GetClientTeam(client) == team)
        {
            continue;
        }
        PrintToChat(client, formatMsg);
        PrintToConsole(client, formatMsg);
    }
}

void AnnounceMaps()
{
    if (ResetPicksIfShould())
    {
        return;
    }

    if (_first_veto_team != TEAM_JINRAI && _first_veto_team != TEAM_NSF)
    {
        ThrowError("Invalid first team: %d", _first_veto_team);
    }

    Panel panel = new Panel();

    panel.SetTitle("Map pick results:");
    panel.DrawText(" ");

    char jinrai_name[MAX_CUSTOM_TEAM_NAME_LEN];
    char nsf_name[MAX_CUSTOM_TEAM_NAME_LEN];
    GetCompetitiveTeamName(TEAM_JINRAI, jinrai_name, sizeof(jinrai_name));
    GetCompetitiveTeamName(TEAM_NSF, nsf_name, sizeof(nsf_name));

    char buffer[PLATFORM_MAX_PATH + MAX_CUSTOM_TEAM_NAME_LEN + 13];

    PrintToConsoleAll("\n== MAP PICK RESULTS ==");
    LogToGame("\n== MAP PICK RESULTS ==");
    Format(buffer, sizeof(buffer), "Map 1: %s", (_first_veto_team == TEAM_JINRAI) ? _nsf_pick : _jinrai_pick);
    panel.DrawText(buffer);
    PrintToConsoleAll("  - %s (%s pick)", buffer, (_first_veto_team == TEAM_JINRAI) ? jinrai_name : nsf_name);
    LogToGame("  - %s (%s pick)", buffer, (_first_veto_team == TEAM_JINRAI) ? jinrai_name : nsf_name);

    Format(buffer, sizeof(buffer), "Map 2: %s", (_first_veto_team == TEAM_JINRAI) ? _jinrai_pick : _nsf_pick);
    panel.DrawText(buffer);
    PrintToConsoleAll("  - %s (%s pick)", buffer, (_first_veto_team == TEAM_JINRAI) ? nsf_name: jinrai_name);
    LogToGame("  - %s (%s pick)", buffer, (_first_veto_team == TEAM_JINRAI) ? nsf_name: jinrai_name);

    Format(buffer, sizeof(buffer), "Map 3: %s", _random_pick);
    panel.DrawText(buffer);
    PrintToConsoleAll("  - %s (random pick)\n", buffer);
    LogToGame("  - %s (random pick)\n", buffer);

    panel.DrawText(" ");
    panel.DrawItem("Exit");

    for (int client = 1; client <= MaxClients; ++client)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
        {
            continue;
        }
        panel.Send(client, MenuHandler_DoNothing, MENU_TIME_FOREVER);
    }
    delete panel;

    EmitSoundToAll(g_sSound_Results);

    CreateTimer(5.0, Timer_MapChangeInfoHelper);
}

public Action Timer_MapChangeInfoHelper(Handle timer)
{
    char[] msg = "[SM] If no admins are present, you can nominate & rtv in chat to change \
the maps according to the map picks.";

    PrintToChatAll("%s", msg);
    PrintToConsoleAll("%s", msg);
    return Plugin_Stop;
}

void GetCompetitiveTeamName(const int team, char[] out_name, const int max_len)
{
    if (team != TEAM_JINRAI && team != TEAM_NSF)
    {
        ThrowError("Unexpected team index: %d", team);
    }

    if (CompPluginIsLoaded())
    {
        GetConVarString((team == TEAM_JINRAI) ? g_hCvar_JinraiName : g_hCvar_NsfName, out_name, max_len);
        if (strlen(out_name) == 0)
        {
            strcopy(out_name, max_len, (team == TEAM_JINRAI) ? "Jinrai" : "NSF");
        }
    }
    else
    {
        strcopy(out_name, max_len, (team == TEAM_JINRAI) ? "Jinrai" : "NSF");
    }
}

bool IsVetoActive()
{
    return _veto_stage != VETO_STAGE_INACTIVE;
}

public int Native_IsVetoActive(Handle plugin, int numParams)
{
    SetNativeCellRef(1, _first_veto_team);
    return IsVetoActive() ? 1 : 0;
}

public int Native_GetVetoMapPoolSize(Handle plugin, int numParams)
{
    return GetNumMaps();
}

public int Native_GetNameOfMapPoolMap(Handle plugin, int numParams)
{
    int map_index = GetNativeCell(1);
    int max_out_len = GetNativeCell(3);

    DataPack dp = new DataPack();
    int num_maps = GetMaps(dp);
    if (num_maps == 0)
    {
        delete dp;
        SetNativeString(2, NULL_STRING, max_out_len, false);
        return 0;
    }

    if (map_index < 0 || map_index >= num_maps)
    {
        delete dp;
        ThrowNativeError(1, "Unexpected map index %d (expected index in range: 0 - %d)", map_index, num_maps);
        return 0;
    }

    char buffer[PLATFORM_MAX_PATH];

    dp.Reset();
    for (int i = 0; i < map_index; ++i)
    {
        dp.ReadString(buffer, sizeof(buffer));
    }
    dp.ReadString(buffer, sizeof(buffer));
    delete dp;

    if (SetNativeString(2, buffer, Min(max_out_len, sizeof(buffer)), false) != SP_ERROR_NONE)
    {
        return 0;
    }
    return strlen(buffer) + 1;
}

VetoStage GetVetoStage()
{
    return _veto_stage;
}

void SetVetoStage(VetoStage stage)
{
    if (_veto_stage != stage)
    {
        _veto_stage = stage;

        Call_StartForward(g_hForwardVetoStageUpdate);
        Call_PushCell(stage);
        Call_PushCell((_veto_stage == VETO_STAGE_COIN_FLIP_RESULT) ? _first_veto_team : -1);
        Call_Finish();
    }
}

void SetMapVetoPick(int team, const char[] pick)
{
    if (strlen(pick) == 0)
    {
        ThrowError("Empty pick");
    }
    else if (!IsMapValid(pick))
    {
        LogError("Map doesn't exist on the server: \"%s\"", pick);
    }

    if (_first_veto_team != TEAM_JINRAI && _first_veto_team != TEAM_NSF)
    {
        ThrowError("_first_veto_team invalid (%d)", _first_veto_team);
    }

    VetoStage stage = GetVetoStage();
    int picking_team = GetPickingTeam();

    if (stage == VETO_STAGE_FIRST_TEAM_BAN || stage == VETO_STAGE_SECOND_TEAM_BAN)
    {
        if (picking_team == TEAM_JINRAI)
        {
            strcopy(_jinrai_veto, sizeof(_jinrai_veto), pick);
        }
        else
        {
            strcopy(_nsf_veto, sizeof(_nsf_veto), pick);
        }
    }
    else if (stage == VETO_STAGE_FIRST_TEAM_PICK || stage == VETO_STAGE_SECOND_TEAM_PICK)
    {
        if (picking_team == TEAM_JINRAI)
        {
            strcopy(_jinrai_pick, sizeof(_jinrai_pick), pick);
        }
        else
        {
            strcopy(_nsf_pick, sizeof(_nsf_pick), pick);
        }

        char msg[256];
        Format(msg, sizeof(msg), "%s %s map is: %s",
            g_sTag,
            ((stage == VETO_STAGE_SECOND_TEAM_PICK) ? "First" : "Second"),
            pick);
        PrintToChatAll("%s", msg);
        PrintToConsoleAll("%s", msg);
        LogToGame("%s", msg);
    }
    else if (stage == VETO_STAGE_RANDOM_THIRD_MAP)
    {
        strcopy(_random_pick, sizeof(_random_pick), pick);

        char msg[256];
        Format(msg, sizeof(msg), "%s Third map is: %s", g_sTag, pick);
        PrintToChatAll("%s", msg);
        PrintToConsoleAll("%s", msg);
        LogToGame("%s", msg);
    }
    else
    {
        ThrowError("Fell through the VETO_STAGE logic");
    }

    Call_StartForward(g_hForwardVetoPick);
    Call_PushCell(GetVetoStage());
    Call_PushCell(team);
    Call_PushString(pick);
    Call_Finish();
}

stock int Min(int a, int b)
{
    return a < b ? a : b;
}

// Backported from SourceMod/SourcePawn SDK for SM < 1.9 compatibility.
// SourceMod (C)2004-2008 AlliedModders LLC.  All rights reserved.
#if SOURCEMOD_V_MAJOR <= 1 && SOURCEMOD_V_MINOR <= 8
/**
 * Sends a message to every client's console.
 *
 * @param format        Formatting rules.
 * @param ...           Variable number of format parameters.
 */
stock void PrintToConsoleAll(const char[] format, any ...)
{
    char buffer[254];

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SetGlobalTransTarget(i);
            VFormat(buffer, sizeof(buffer), format, 2);
            PrintToConsole(i, "%s", buffer);
        }
    }
}
#endif

// Get the veto map pool.
// If you just want the number of maps, pass in no arguments
// (or more preferably call GetNumMaps() instead for clearly stating that
// intent).
//
// Note: This function will *not* initialize/reset/free the DataPack,
// and will just write the map strings into its current position as-is;
// the caller of this function is responsible for the DataPack memory
// management.
//
// - Return value: the number of maps, or -1 on error
// - Out value passed by-ref (optional): DataPack of 0 or more map strings
// - Out value passed by-ref (optional): boolean of whether all of the out_dp pushed maps exist in server
// - Error states: Missing or invalid config file(s). Will LogError the error, and return -1.
int GetMaps(DataPack out_dp = null, bool& all_maps_exist_on_server = false)
{
    all_maps_exist_on_server = false;

    char path[PLATFORM_MAX_PATH];
    if (BuildPath(Path_SM, path, sizeof(path), "configs/veto.cfg") < 0)
    {
        LogError("Failed to build path");
        return -1;
    }
    if (!FileExists(path))
    {
        LogError("Config path doesn't exist: \"%s\"", path);
        return -1;
    }

    KeyValues kv = new KeyValues("cfg_veto");
    if (!kv.ImportFromFile(path))
    {
        delete kv;
        LogError("Failed to import cfg to keyvalues: \"%s\"", path);
        return -1;
    }

    int version = kv.GetNum("version");
    if (version == 0)
    {
        delete kv;
        LogError("Invalid config version or no version found");
        return -1;
    }
    else if (version != VETOS_CFG_VERSION)
    {
        delete kv;
        LogError("Unsupported config version %d (expected version %d)",
            version, VETOS_CFG_VERSION);
        return -1;
    }

    kv.GetString("map_pool_file", path, sizeof(path));
    if (!FileExists(path))
    {
        delete kv;
        LogError("Veto map pool path doesn't exist: \"%s\"", path);
        return -1;
    }

    delete kv;

    File f = OpenFile(path, "rt");
    if (f == null)
    {
        LogError("Failed to open veto map pool path: \"%s\"", path);
        return -1;
    }

    all_maps_exist_on_server = true;
    int num_maps;
    // Iterate the file lines & populate the datapack map strings.
    while (!f.EndOfFile())
    {
        char line[PLATFORM_MAX_PATH];
        // Returns false on empty lines, so we try a manual Read because
        // we wanna support reading past empty lines.
        while (!f.ReadLine(line, sizeof(line)))
        {
            int dummy[1];
            // Try and step over the presumed empty line
            if (f.Read(dummy, sizeof(dummy), 1))
            {
                continue;
            }
            // Read failed. EOF?
            break;
        }

        TrimString(line);

        // We're using the semicolon as the INI file comment character
        int semicolon_pos = FindCharInString(line, ';');
        // Ignore lines that start with a ;comment, and lines that are empty
        if (semicolon_pos == 0 || strlen(line) == 0)
        {
            continue;
        }
        // Terminate string at any trailing ;comment
        if (semicolon_pos > 0)
        {
            line[semicolon_pos] = '\0';
            TrimString(line);
        }

        if (!IsMapValid(line))
        {
            all_maps_exist_on_server = false;
        }

        if (out_dp != null)
        {
            out_dp.WriteString(line);
        }

        ++num_maps;
    }
    f.Close();

    return num_maps;
}

int GetNumMaps()
{
    return GetMaps();
}

// The nt_competitive plugin defines this cvar, so we can determine whether
// the plugin is loaded by its existence.
bool CompPluginIsLoaded()
{
    return g_hCvar_JinraiName != null;
}

#if defined(DEBUG_FAKE_VETOS)
// It's recommended for this debug list to be an exact match of
// the server's veto_maplist.ini map pool, as otherwise
// Native_GetNameOfMapPoolMap(...) output may not match.
#define NUM_RANDOM_MAPS 9
static char _random_maps[NUM_RANDOM_MAPS][] = {
    "nt_ballistrade_ctg",
    "nt_bullet_tdm",
    "nt_dawn_ctg",
    "nt_decom_ctg",
    "nt_disengage_ctg",
    "nt_dusk_ctg",
    "nt_engage_ctg",
    "nt_ghost_ctg",
    "nt_isolation_ctg",
};
bool _is_random_map_picked[NUM_RANDOM_MAPS];

public Action Cmd_AdminDebug_FakeVeto(int client, int argc)
{
    Call_StartForward(g_hForwardVetoStageUpdate);
    Call_PushCell(VETO_STAGE_COIN_FLIP);
    Call_PushCell(-1);
    Call_Finish();

    CreateTimer(DEBUG_FAKE_VETOS_TIMER, Timer_FakeCoinFlip);
    return Plugin_Handled;
}

public Action Timer_FakeCoinFlip(Handle timer)
{
    SetRandomSeed(GetTime());
    _first_veto_team = GetRandomInt(TEAM_JINRAI, TEAM_NSF);

    Call_StartForward(g_hForwardVetoStageUpdate);
    Call_PushCell(VETO_STAGE_COIN_FLIP_RESULT);
    Call_PushCell(_first_veto_team);
    Call_Finish();

    CreateTimer(DEBUG_FAKE_VETOS_TIMER, Timer_FakeFirstVeto);
    return Plugin_Stop;
}

public Action Timer_FakeFirstVeto(Handle timer)
{
    SetRandomSeed(GetURandomInt());
    int map = GetRandomInt(0, NUM_RANDOM_MAPS - 1);
    _is_random_map_picked[map] = true;

    if (_first_veto_team == TEAM_JINRAI)
    {
        strcopy(_jinrai_veto, sizeof(_jinrai_veto), _random_maps[map]);
    }
    else
    {
        strcopy(_nsf_veto, sizeof(_nsf_veto), _random_maps[map]);
    }

    Call_StartForward(g_hForwardVetoPick);
    Call_PushCell(VETO_STAGE_FIRST_TEAM_BAN);
    Call_PushCell(_first_veto_team);
    Call_PushString(_random_maps[map]);
    Call_Finish();

    Call_StartForward(g_hForwardVetoStageUpdate);
    Call_PushCell(VETO_STAGE_FIRST_TEAM_BAN);
    Call_PushCell(-1);
    Call_Finish();

    CreateTimer(DEBUG_FAKE_VETOS_TIMER, Timer_FakeSecondVeto);
    return Plugin_Stop;
}

public Action Timer_FakeSecondVeto(Handle timer)
{
    int map;
    do
    {
        SetRandomSeed(GetURandomInt());
        map = GetRandomInt(0, NUM_RANDOM_MAPS - 1);
    }
    while (_is_random_map_picked[map]);
    _is_random_map_picked[map] = true;

    if (_first_veto_team == TEAM_JINRAI)
    {
        strcopy(_nsf_veto, sizeof(_nsf_veto), _random_maps[map]);
    }
    else
    {
        strcopy(_jinrai_veto, sizeof(_jinrai_veto), _random_maps[map]);
    }

    Call_StartForward(g_hForwardVetoPick);
    Call_PushCell(VETO_STAGE_SECOND_TEAM_BAN);
    Call_PushCell(GetOpposingTeam(_first_veto_team));
    Call_PushString(_random_maps[map]);
    Call_Finish();

    Call_StartForward(g_hForwardVetoStageUpdate);
    Call_PushCell(VETO_STAGE_SECOND_TEAM_BAN);
    Call_PushCell(-1);
    Call_Finish();

    CreateTimer(DEBUG_FAKE_VETOS_TIMER, Timer_FakeSecondPick);
    return Plugin_Stop;
}

public Action Timer_FakeSecondPick(Handle timer, DataPack picked_maps)
{
    int map;
    do
    {
        SetRandomSeed(GetURandomInt());
        map = GetRandomInt(0, NUM_RANDOM_MAPS - 1);
    }
    while (_is_random_map_picked[map]);
    _is_random_map_picked[map] = true;

    if (_first_veto_team == TEAM_JINRAI)
    {
        strcopy(_nsf_pick, sizeof(_nsf_pick), _random_maps[map]);
    }
    else
    {
        strcopy(_jinrai_pick, sizeof(_jinrai_pick), _random_maps[map]);
    }

    Call_StartForward(g_hForwardVetoPick);
    Call_PushCell(VETO_STAGE_SECOND_TEAM_PICK);
    Call_PushCell(GetOpposingTeam(_first_veto_team));
    Call_PushString(_random_maps[map]);
    Call_Finish();

    Call_StartForward(g_hForwardVetoStageUpdate);
    Call_PushCell(VETO_STAGE_SECOND_TEAM_PICK);
    Call_PushCell(-1);
    Call_Finish();

    CreateTimer(DEBUG_FAKE_VETOS_TIMER, Timer_FakeFirstPick);
    return Plugin_Stop;
}

public Action Timer_FakeFirstPick(Handle timer)
{
    int map;
    do
    {
        SetRandomSeed(GetURandomInt());
        map = GetRandomInt(0, NUM_RANDOM_MAPS - 1);
    }
    while (_is_random_map_picked[map]);
    _is_random_map_picked[map] = true;

    if (_first_veto_team == TEAM_JINRAI)
    {
        strcopy(_jinrai_pick, sizeof(_jinrai_pick), _random_maps[map]);
    }
    else
    {
        strcopy(_nsf_pick, sizeof(_nsf_pick), _random_maps[map]);
    }

    Call_StartForward(g_hForwardVetoPick);
    Call_PushCell(VETO_STAGE_FIRST_TEAM_PICK);
    Call_PushCell(_first_veto_team);
    Call_PushString(_random_maps[map]);
    Call_Finish();

    Call_StartForward(g_hForwardVetoStageUpdate);
    Call_PushCell(VETO_STAGE_FIRST_TEAM_PICK);
    Call_PushCell(-1);
    Call_Finish();

    CreateTimer(DEBUG_FAKE_VETOS_TIMER, Timer_RandomThirdPick);
    return Plugin_Stop;
}

public Action Timer_RandomThirdPick(Handle timer, DataPack picked_maps)
{
    int map;
    do
    {
        SetRandomSeed(GetURandomInt());
        map = GetRandomInt(0, NUM_RANDOM_MAPS - 1);
    }
    while (_is_random_map_picked[map]);
    _is_random_map_picked[map] = true;

    strcopy(_random_pick, sizeof(_random_pick), _random_maps[map]);

    Call_StartForward(g_hForwardVetoPick);
    Call_PushCell(VETO_STAGE_RANDOM_THIRD_MAP);
    Call_PushCell(TEAM_SPECTATOR);
    Call_PushString(_random_maps[map]);
    Call_Finish();

    Call_StartForward(g_hForwardVetoStageUpdate);
    Call_PushCell(VETO_STAGE_RANDOM_THIRD_MAP);
    Call_PushCell(-1);
    Call_Finish();

    ClearVeto();
    Call_StartForward(g_hForwardVetoStageUpdate);
    Call_PushCell(VETO_STAGE_INACTIVE);
    Call_PushCell(-1);
    Call_Finish();

    for (int i = 0; i < sizeof(_is_random_map_picked); ++i) {
        _is_random_map_picked[i] = false;
    }

    return Plugin_Stop;
}
#endif
