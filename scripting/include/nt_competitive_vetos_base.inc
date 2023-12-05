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
char _chars[STAGES_MAX] = "cvVrpPRx";
int _char_pos;
int _num_pattern_maps_required;

char g_sTag[] = "[MAP PICK]";
char g_sSound_Veto[] = "ui/buttonrollover.wav";
char g_sSound_Pick[] = "ui/buttonclick.wav";
char g_sSound_Results[] = "player/CPcaptured.wav";

enum struct MapChoice {
    int team;
    char map[PLATFORM_MAX_PATH];
    VetoStage_v2 stage;
}
