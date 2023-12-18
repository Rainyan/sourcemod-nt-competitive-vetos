#if defined _NT_COMPETITIVE_VETOS_BASE_INC_
    #endinput
#endif
#define _NT_COMPETITIVE_VETOS_BASE_INC_

#include <nt_competitive_vetos_enum>

#pragma semicolon 1
#pragma newdecls required

#define STAGES_MAX 64
#define NEO_MAX_PLAYERS 32
#define MAX_CUSTOM_TEAM_NAME_LEN 64
// Used for catching bugs where team managed to vote an unavailable option.
#define ITEM_DISABLED_STR "null"
// Versioning used for the veto.cfg format changes.
#define VETOS_CFG_VERSION 1

#define DEFAULT_TEAM_A TEAM_JINRAI
#if DEFAULT_TEAM_A != TEAM_JINRAI && DEFAULT_TEAM_A != TEAM_NSF
#error Unexpected default team
#endif

#if defined(DEBUG_FAKE_VETOS)
// It's recommended for this debug list to be an exact match of
// the server's veto_maplist.ini map pool, as otherwise
// Native_GetNameOfMapPoolMap(...) output may not match.
#define NUM_RANDOM_MAPS 9
char _random_maps[NUM_RANDOM_MAPS][] = {
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
#endif

char _pending_map_pick_nomination_for_vote[PLATFORM_MAX_PATH];

// One-char symbols that correspond to VetoStage options.
char _chars[VETOSTAGE_ENUM_COUNT] = "cvVrpPR";
int _char_pos;
int _num_pattern_maps_required;
int _team_a = DEFAULT_TEAM_A;

char g_sTag[] = "[MAP PICK]";
char g_sSound_Veto[] = "ui/buttonrollover.wav";
char g_sSound_Pick[] = "ui/buttonclick.wav";
char g_sSound_Results[] = "player/CPcaptured.wav";

// Functions for the corresponding VetoStage action to perform.
static Function _funcs[VETOSTAGE_ENUM_COUNT] = { INVALID_FUNCTION, ... };

DataPack _veto = null;

ArrayList _results = null;

enum struct MapChoice {
    int team;
    char map[PLATFORM_MAX_PATH];
    VetoStage_v2 stage;
}

void InitVetoFunctionPtrs()
{
    _funcs[COINFLIP] = CoinFlip;
    _funcs[VETO_A] = VetoMap_A;
    _funcs[VETO_B] = VetoMap_B;
    _funcs[VETO_RANDOM] = VetoMap_Random;
    _funcs[PICK_A] = PickMap_A;
    _funcs[PICK_B] = PickMap_B;
    _funcs[PICK_RANDOM] = PickMap_Random;
}

static void VetoMap_A()
{
    ChooseMap(GetTeamA(), true);
}

static void VetoMap_B()
{
    ChooseMap(GetTeamB(), true);
}

static void VetoMap_Random()
{
    ChooseMap(TEAM_NONE, true);
}

static int GetTeamA()
{
    return _team_a;
}

static int GetTeamB()
{
    return GetOtherTeam(GetTeamA());
}

static void PickMap_A()
{
    ChooseMap(GetTeamA(), false);
}

static void PickMap_B()
{
    ChooseMap(GetTeamB(), false);
}

static void PickMap_Random()
{
    ChooseMap(TEAM_NONE, false);
}

static void ChooseMap(const int team, const bool is_veto)
{
    if (strlen(_pending_map_pick_nomination_for_vote) != 0)
    {
        ThrowError("_pending_map_pick_nomination_for_vote not empty");
    }
    if (_num_pattern_maps_required <= 0)
    {
        ThrowError("Invalid _num_pattern_maps_required size: %d",
            _num_pattern_maps_required);
    }

    int picking_team = team;
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
    else if (veto_pool_size < _num_pattern_maps_required)
    {
        delete dp_maps;
        ThrowError("Need at least %d maps on veto pool (got %d)",
            _num_pattern_maps_required);
    }
    else if (!all_maps_exist_on_server)
    {
        PrintToChatAll("%s Warning: the veto map pool contains map(s) that \
don't exist on this server!", g_sTag);
    }

    bool is_random_choice = (team == TEAM_NONE);

    if (is_random_choice)
    {
        dp_maps.Reset();
        DataPack dp_unchosen_maps = new DataPack();
        int num_remaining_maps;
        char map_name_buffer[PLATFORM_MAX_PATH];
        MapChoice choice;
        for (int i = 0; i < veto_pool_size; ++i)
        {
            dp_maps.ReadString(map_name_buffer, sizeof(map_name_buffer));
            bool is_result;

            int res_len = _results.Length;

            for (int j = 0; j < res_len; ++j)
            {
                _results.GetArray(j, choice);
                if (StrEqual(map_name_buffer, choice.map))
                {
                    is_result = true;
                    break;
                }
            }
            if (!is_result)
            {
                dp_unchosen_maps.WriteString(map_name_buffer);
                ++num_remaining_maps;
            }
        }
        if (num_remaining_maps == 0)
        {
            delete dp_maps;
            delete dp_unchosen_maps;
            ThrowError("No maps left to choose from");
        }

        int third_map_index = GetURandomInt() % num_remaining_maps;

        dp_unchosen_maps.Reset();
        for (int i = 0; i < third_map_index; ++i)
        {
            dp_unchosen_maps.ReadString(map_name_buffer, sizeof(map_name_buffer));
        }
        dp_unchosen_maps.ReadString(map_name_buffer, sizeof(map_name_buffer));
        delete dp_unchosen_maps;
        delete dp_maps;

        if (GetCurrentVetoStage() == PICK_RANDOM)
        {
            SetMapVetoPick(team, map_name_buffer);
        }

        return;
    } // is_random_choice

    if (team != TEAM_JINRAI && team != TEAM_NSF)
    {
        delete dp_maps;
        ThrowError("Invalid picking team: %d", team);
    }

    Menu picker_menu = new Menu(MenuHandler_DoPick,
        (MenuAction_Select | MenuAction_End)
    );
    picker_menu.ExitButton = false;

    Panel spec_panel = new Panel();
    spec_panel.SetTitle(g_sTag);
    spec_panel.DrawText(" ");

    char jinrai_name[MAX_CUSTOM_TEAM_NAME_LEN];
    char nsf_name[MAX_CUSTOM_TEAM_NAME_LEN];
    GetCompetitiveTeamName(TEAM_JINRAI, jinrai_name, sizeof(jinrai_name));
    GetCompetitiveTeamName(TEAM_NSF, nsf_name, sizeof(nsf_name));

    picker_menu.SetTitle("Your team's map %s:", is_veto ? "VETO" : "PICK");
    picker_menu.Pagination = Min(veto_pool_size, 7);

    spec_panel.DrawText(is_veto ? "Waiting for veto by:" : "Waiting for pick by:");
    spec_panel.DrawText((picking_team == TEAM_JINRAI) ? jinrai_name : nsf_name);
    spec_panel.DrawText(" ");

    char map_name_buffer[PLATFORM_MAX_PATH];
    char buffer[PLATFORM_MAX_PATH + MAX_CUSTOM_TEAM_NAME_LEN + 11 + 1];
    dp_maps.Reset();
    for (int i = 0; i < veto_pool_size; ++i)
    {
        dp_maps.ReadString(map_name_buffer, sizeof(map_name_buffer));
        int res_len = _results.Length;
        MapChoice choice;
        bool found;
        for (int j = 0; j < res_len; ++j)
        {
            _results.GetArray(j, choice);
            if (StrEqual(map_name_buffer, choice.map))
            {
                Format(buffer, sizeof(buffer), "%s (%s %s)",
                    choice.map,
                    choice.team,
                    IsVeto(choice.stage) ? "VETO" : "PICK"
                );
                picker_menu.AddItem(ITEM_DISABLED_STR, buffer, ITEMDRAW_DISABLED);
                spec_panel.DrawText(buffer);

                found = true;
                break;
            }
        }
        if (!found)
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

// Assumes valid pattern; it's up to the caller to verify validity with
// IsVetoPatternValid before calling this!
void BuildVeto(const char[] pattern, int pattern_size)
{
    ClearVeto();
    _veto = new DataPack();
    for (int i = 0; i < pattern_size && pattern[i] != '\0'; ++i)
    {
        VetoStage_v2 s;
        if (!GetVetoStage(pattern[i], s))
        {
            ThrowError("Failed to get VetoStage for i=%d from \"%s\"; \
expected symbols list: \"%s\"",
                i, pattern, _chars
            );
        }
        _veto.WriteFunction(_funcs[s]);
    }
    _veto.Reset();
    _char_pos = 0;
}
