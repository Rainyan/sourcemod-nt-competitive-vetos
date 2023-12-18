#include <sourcemod>
#include <sdktools>

#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required

#include <nt_competitive_vetos_base>
#include <nt_competitive_vetos_enum>
#include <nt_competitive_vetos_menus>
#include <nt_competitive_vetos_timers>

#define PLUGIN_VERSION "2.0.0"

static ConVar _pattern = null;

Handle g_hForwardVetoStageUpdate = INVALID_HANDLE,
    g_hForwardVetoPick = INVALID_HANDLE;

// Debug flag for doing funky testing stuff. Don't enable for regular use.
//#define DEBUG

// Debug flag for forcing all the vetos on the Jinrai team side.
// Note that it's expected that this will report incorrect vote results for NSF,
// as you would be voting from Jinrai in their stead.
//#define DEBUG_ALL_VETOS_BY_JINRAI

static bool _wants_to_start_veto_jinrai;
static bool _wants_to_start_veto_nsf;

ConVar g_hCvar_JinraiName = null,
    g_hCvar_NsfName = null;

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

#if defined(DEBUG)
void PluginInitSanityCheck()
{
    // Verify each character symbol of VetoStage is defined.
    if (strlen(_chars) != view_as<int>(VETOSTAGE_ENUM_COUNT))
    {
        SetFailState("Pattern size mismatch (%d, %d)",
            strlen(_chars),
            view_as<int>(VETOSTAGE_ENUM_COUNT)
        );
    }
    // Verify each character symbol of the VetoStage is unique.
    for (int i = 0; i < sizeof(_chars); ++i)
    {
        if (_chars[i] == '\0')
        {
            break;
        }
        for (int j = i + 1; j < sizeof(_chars); ++j)
        {
            if (_chars[j] == '\0')
            {
                break;
            }
            if (FindCharInString(_chars[j], _chars[i]) != -1)
            {
                SetFailState("Duplicate symbols in pattern: \"%s\", %d, %d",
                    _chars, i, j);
            }
        }
    }
}
#endif

public void OnPluginStart()
{
#if defined(DEBUG)
    PluginInitSanityCheck();
#endif
    InitVetoFunctionPtrs();

    VetoStage_v2 default_pattern[] = {
        COINFLIP,
        VETO_A,
        VETO_B,
        PICK_A,
        PICK_B,
        PICK_RANDOM
    };
    char default_pattern_buffer[sizeof(default_pattern)];
    VetoStagesToString(default_pattern, sizeof(default_pattern), default_pattern_buffer);
    if (!IsVetoPatternValid(default_pattern_buffer, sizeof(default_pattern_buffer)))
    {
        SetFailState("Default veto pattern is invalid: \"%s\"", default_pattern_buffer);
    }
    _pattern = CreateConVar("sm_vetos_pattern", default_pattern_buffer);
    _pattern.AddChangeHook(OnPatternChanged);

    CreateConVar("sm_nt_competitive_vetos_version", PLUGIN_VERSION, "NT Competitive Vetos plugin version.", FCVAR_DONTRECORD);

    RegAdminCmd("sm_resetveto", Cmd_AdminResetVeto, ADMFLAG_GENERIC, "Admin command to reset a veto in progress.");
    RegAdminCmd("sm_cancelveto", Cmd_AdminResetVeto, ADMFLAG_GENERIC, "Alias for sm_resetveto.");
    RegAdminCmd("sm_clearveto", Cmd_AdminResetVeto, ADMFLAG_GENERIC, "Alias for sm_resetveto.");

    RegConsoleCmd("sm_veto", Cmd_StartVeto, "Ready the team for map picks/vetos.");
    RegConsoleCmd("sm_unveto", Cmd_CancelVeto, "Unready the team for map picks/vetos.");

    g_hForwardVetoStageUpdate = CreateGlobalForward("OnMapVetoStageUpdate_v2", ET_Ignore, Param_Cell);
    g_hForwardVetoPick = CreateGlobalForward("OnMapVetoPick", ET_Ignore, Param_Cell, Param_Cell, Param_String);
    // TODO: Create OnMapVetoStart, ...End, ...Cancel forwards.

    _results = new ArrayList(sizeof(MapChoice));

    RegAdminCmd("sm_vetos_debug_pattern", Cmd_DebugPattern, ADMFLAG_GENERIC);
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

public void OnConfigsExecuted()
{
    char pattern[STAGES_MAX + 1];
    _pattern.GetString(pattern, sizeof(pattern));
    int error_index;
    char error[128];
    if (!IsVetoPatternValid(pattern, sizeof(pattern), _num_pattern_maps_required,
        error_index, error, sizeof(error)))
    {
        ThrowError("Pattern validity check failed at index %d: %s",
            error_index, error);
    }
    BuildVeto(pattern, sizeof(pattern));
}

public void OnPatternChanged(ConVar convar, const char[] oldValue,
    const char[] newValue)
{
    int error_index;
    char error[128];
    if (!IsVetoPatternValid(newValue, strlen(newValue) + 1,
        _num_pattern_maps_required, error_index, error, sizeof(error)))
    {
        // Fall back to previous known-valid pattern
        convar.SetString(oldValue);
        ThrowError("Pattern validity check failed at index %d: %s",
            error_index, error);
    }
    BuildVeto(newValue, strlen(newValue) + 1);
}

public void OnMapStart()
{
    if (!PrecacheSound(g_sSound_Veto) ||
        !PrecacheSound(g_sSound_Pick) ||
        !PrecacheSound(g_sSound_Results))
    {
        SetFailState("Failed to precache sound");
    }

    ClearVeto();
}

// Prints a human-readable explanation of current VetoStage pattern to console.
public Action Cmd_DebugPattern(int client, int argc)
{
    char pattern[STAGES_MAX + 1];
    _pattern.GetString(pattern, sizeof(pattern));
    PrintToConsole(client, "Current veto pattern is \"%s\":", pattern);
    char description[27 + 1];
    for (int i = 0; i < sizeof(pattern) && pattern[i] != '\0'; ++i)
    {
        VetoStage_v2 s;
        if (!GetVetoStage(pattern[i], s))
        {
            ThrowError("Failed to get VetoStage for '%c'", pattern[i]);
        }
        GetVetoStageDescription(s, description, sizeof(description));
        PrintToConsole(client, "  - Stage %d: '%c' -> %s",
            i + 1, pattern[i], description
        );
    }
    if (client != 0 && GetCmdReplySource() == SM_REPLY_TO_CHAT)
    {
        PrintToChat(client,
            "[%s] Pattern info has been printed to your console.",
            g_sTag
        );
    }
    return Plugin_Handled;
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

    // resetveto fwd here?

    return Plugin_Handled;
}

void ClearVeto()
{
    delete _veto;
    _results.Clear();

    _team_a = DEFAULT_TEAM_A;
    _wants_to_start_veto_jinrai = _wants_to_start_veto_nsf = false;

    if (g_hCvar_KidPrintToPanel != null)
    {
        g_hCvar_KidPrintToPanel.BoolValue = _kid_print_to_panel_default;
    }
}

// For a character, passes its corresponding VetoStage by reference.
// Returns true for a valid VetoStage character, false otherwise.
bool GetVetoStage(char c, VetoStage_v2& out_stage)
{
    int index = FindCharInString(_chars, c);
    if (index == -1)
    {
        return false;
    }
    out_stage = view_as<VetoStage_v2>(index);
    return true;
}

// Passes a description of a VetoStage by reference.
// Returns the number of characters copied.
int GetVetoStageDescription(VetoStage_v2 s, char[] out_description, int maxlen)
{
    char descriptions[VETOSTAGE_ENUM_COUNT][] = {
        "Choose team A with coinflip",
        "Veto by team A",
        "Veto by team B",
        "Random veto",
        "Pick by team A",
        "Pick by team B",
        "Random pick",
    };
    return strcopy(out_description, maxlen, descriptions[s]);
}

// Returns whether the VetoStage pattern is valid.
// If pattern is not valid, optionally passes the first_error_index by
// reference, and optionally passes an error message by reference.
// A zero-sized pattern is considered invalid.
// A pattern size larger than STAGES_MAX is considered invalid.
// A pattern that produces 0 map picks is considered invalid.
bool IsVetoPatternValid(const char[] pattern, int pattern_size,
    int& min_maps_required=0,
    int& first_error_index=0,
    char[] out_error=NULL_STRING, int error_maxlen=0)
{
    if (pattern_size <= 0)
    {
        strcopy(out_error, error_maxlen, "Pattern size <1");
        return false;
    }
    char[] number = new char[pattern_size];
    int number_chars, n_pick_stages, i;
    for (; i < pattern_size; ++i)
    {
        if (pattern[i] == '\0')
        {
            break;
        }
        if (IsCharMB(pattern[i]))
        {
            first_error_index = i;
            strcopy(out_error, error_maxlen, "Multibyte character");
            return false;
        }
        if (IsCharNumeric(pattern[i]))
        {
            number[number_chars++] = pattern[i];
            continue;
        }
        int n = (number_chars == 0) ? 1 : StringToInt(number);
        if (n <= 0)
        {
            first_error_index = i;
            Format(out_error, error_maxlen, "Number parsing failed: \"%s\"->%d",
                number, n);
            return false;
        }
        number_chars = 0;
        strcopy(number, pattern_size, "");

        VetoStage_v2 s;
        if (!GetVetoStage(pattern[i], s))
        {
            first_error_index = i;
            Format(out_error, error_maxlen, "Failed to find VetoStage for '%c'",
                pattern[i]);
            return false;
        }

        if (view_as<int>(s) < 0 || s >= VETOSTAGE_ENUM_COUNT)
        {
            first_error_index = i;
            Format(out_error, error_maxlen, "VetoStage out of range (%d)",
                view_as<int>(s));
            return false;
        }

        if (s == PICK_A || s == PICK_B || s == PICK_RANDOM)
        {
            n_pick_stages += n;
            min_maps_required += n;
        }
        else if (s == VETO_A || s == VETO_B || s == VETO_RANDOM)
        {
            min_maps_required += n;
        }
    }
    if (i > STAGES_MAX)
    {
        Format(out_error, error_maxlen,
            "Pattern length (%d) is longer than maximum allowed size (%d)",
            i, STAGES_MAX);
        return false;
    }
    if (n_pick_stages < 1)
    {
        Format(out_error, error_maxlen, "No map pick actions in the pattern");
        return false;
    }
    return true;
}

// Returns TEAM_JINRAI for TEAM_NSF and vice versa.
// Input must be TEAM_JINRAI or TEAM_NSF.
int GetOtherTeam(int team)
{
    if (team != TEAM_JINRAI && team != TEAM_NSF)
    {
        ThrowError("Unexpected team: %d", team);
    }
    return team == TEAM_NSF ? TEAM_JINRAI : TEAM_NSF;
}

// For a veto DataPack, reads its next VetoStage function, if one exists,
// and then calls it.
// Returns whether there was such a function in the veto DataPack to read.
// Passes any return value from the called VetoStage function by reference.
// If the veto DataPack was readable, increments its position by 1 as side
// effect.
bool ProcessVetoStage(DataPack veto, any& result=0)
{
    if (!veto.IsReadable())
    {
        return false;
    }

    Function fun = veto.ReadFunction();
    if (fun == INVALID_FUNCTION)
    {
        return false;
    }

    Call_StartFunction(INVALID_HANDLE, fun);
    if (Call_Finish(result) != SP_ERROR_NONE)
    {
        ThrowError("Call failed");
    }
    return true;
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

    if (IsReadyToStartVeto())
    {
        StartNewVeto();
    }
    else
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

int GetRandomPlayerTeam()
{
    return GetURandomInt() % 2 == 0 ? TEAM_JINRAI : TEAM_NSF;
}

bool IsReadyToStartVeto()
{
    return (
        !IsVetoActive() &&
        _wants_to_start_veto_jinrai &&
        _wants_to_start_veto_nsf
    );
}

void StartNewVeto()
{
    // TODO!
}

void CoinFlip()
{
    if (ResetPicksIfShould())
    {
        return;
    }

    static int coinflip_stage = 0;

    Panel panel = new Panel();
    panel.SetTitle(g_sTag);

    // Characters to represent the "coin flip" spinning around, for some appropriate suspense.
    char coinflip_anim[][] = { "-", "\\", "|", "/" };
    // How many 180 coin flips for the full animation, ie. 3 = 1.5 full rotations.
#define NUM_COINFLIP_ANIMATION_HALF_ROTATIONS 3

    int show_cointflip_results_duration = 5;

    if (coinflip_stage++ < sizeof(coinflip_anim) * NUM_COINFLIP_ANIMATION_HALF_ROTATIONS)
    {
        char text[19];
        Format(text, sizeof(text), "Flipping coin... %s", coinflip_anim[coinflip_stage % sizeof(coinflip_anim)]);
        panel.DrawText(" ");
        panel.DrawText(text);

        CreateTimer(0.33, Timer_CoinFlip, coinflip_stage, TIMER_FLAG_NO_MAPCHANGE);
    }
    else
    {
        coinflip_stage = 0;

#if defined DEBUG_ALL_VETOS_BY_JINRAI
        _team_a = TEAM_JINRAI;
#else
        _team_a = GetRandomPlayerTeam();
#endif
        char team_name[MAX_CUSTOM_TEAM_NAME_LEN];
        GetCompetitiveTeamName(_team_a, team_name, sizeof(team_name));

        char text[20 + MAX_CUSTOM_TEAM_NAME_LEN];
        // Still adding the "Flipping coin..." part here for visual continuity from the coin flipping stage.
        Format(text, sizeof(text), "Flipping coin... Team %s vetoes first.", team_name);

        panel.DrawText(" ");
        panel.DrawText(text);

        PrintToConsoleAll("%s %s", g_sTag, text);
        LogToGame("%s %s", g_sTag, text);

        CreateTimer(float(show_cointflip_results_duration), Timer_StartVeto, _, TIMER_FLAG_NO_MAPCHANGE);
    }

    for (int client = 1; client <= MaxClients; ++client)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
        {
            continue;
        }
        panel.Send(client, MenuHandler_DoNothing, show_cointflip_results_duration);
    }
    delete panel;
}

bool IsVeto(VetoStage_v2 s)
{
    return s == VETO_A || s == VETO_B || s ==  VETO_RANDOM;
}

VetoStage_v2 GetCurrentVetoStage()
{
    VetoStage_v2 s;
    if (!GetVetoStage(_chars[_char_pos], s))
    {
        ThrowError("Failed to get VetoStage for '%c'", _chars[_char_pos]);
    }
    return s;
}

void DoVeto()
{
    if (!IsVetoActive())
    {
        ThrowError("Called DoVeto while !IsVetoActive");
    }

    if (ResetPicksIfShould())
    {
        return;
    }

    if (ProcessVetoStage(_veto))
    {
        Call_StartForward(g_hForwardVetoStageUpdate);
        Call_PushCell(GetCurrentVetoStage());
        Call_Finish();
    }
    else
    {
        if (_results.Length > 0)
        {
            AnnounceMaps();
        }
        ClearVeto();
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
    VetoStage_v2 stage = GetCurrentVetoStage();
    if (stage == VETO_A || stage == PICK_A)
    {
        return _team_a;
    }
    if (stage == VETO_B || stage == PICK_B)
    {
        return GetOpposingTeam(_team_a);
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
        PrintToChat(client, "%s", formatMsg);
        PrintToConsole(client, "%s", formatMsg);
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
        PrintToChat(client, "%s", formatMsg);
        PrintToConsole(client, "%s", formatMsg);
    }
}

void AnnounceMaps()
{
    if (ResetPicksIfShould())
    {
        return;
    }

    if (_team_a != TEAM_JINRAI && _team_a != TEAM_NSF)
    {
        ThrowError("Invalid first team: %d", _team_a);
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

    int res_len = _results.Length;
    MapChoice choice;
    for (int i = 0; i < res_len; ++i)
    {
        _results.GetArray(i, choice);
        Format(buffer, sizeof(buffer), "Map %d: %s", i, choice.map);
        panel.DrawText(buffer);
        PrintToConsoleAll("  - %s (%s pick)", buffer, choice.team);
        LogToGame("  - %s (%s pick)", buffer, choice.team);
    }
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

    // Don't need to show this if the automatic veto nextmap plugin exists.
    if (FindConVar("sm_nt_competitive_vetos_autonextmap_version") == null)
    {
        CreateTimer(5.0, Timer_MapChangeInfoHelper);
    }
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

public int Native_IsVetoActive(Handle plugin, int numParams)
{
    SetNativeCellRef(1, _team_a);
    return IsVetoActive() ? 1 : 0;
}

bool IsVetoActive()
{
    return (_veto != null);
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

    VetoStage_v2 stage = GetCurrentVetoStage();

    char team_name[MAX_CUSTOM_TEAM_NAME_LEN] = "Random";
    if (team == TEAM_JINRAI || team == TEAM_NSF)
    {
        GetCompetitiveTeamName(team, team_name, sizeof(team_name));
    }

    MapChoice choice;
    choice.team = team;
    strcopy(choice.map, sizeof(MapChoice::map), pick);

    _results.PushArray(choice);

    Call_StartForward(g_hForwardVetoPick);
    Call_PushCell(stage);
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

// Create a veto pattern string from an array of veto stages.
// Passes the pattern string by reference.
// The out_string must be able to contain at least n_stages chars.
void VetoStagesToString(const VetoStage_v2[] stages, int n_stages, char[] out_string)
{
    for (int n = 0; n < n_stages; ++n)
    {
        out_string[n] = _chars[stages[n]];
    }
}