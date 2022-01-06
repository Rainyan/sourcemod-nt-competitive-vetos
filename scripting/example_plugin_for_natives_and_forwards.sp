#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#include <nt_competitive_vetos_enum>
#include <nt_competitive_vetos_natives>

/*
This is an example plugin for accessing all of the veto states available to
third party plugins.

Example veto flow follows (if you just want the implementation details, scroll down):

===========================================
OnAllPluginsLoaded() output of this plugin:
===========================================
Map 0: "nt_ballistrade_ctg"
Map 1: "nt_shipment_ctg_comp_rc1"
Map 2: "nt_snowfall_ctg_b3"
Map 3: "nt_oliostain_ctg_b3"
Map 4: "nt_rise_ctg"
Map 5: "nt_threadplate_ctg"
Map 6: "nt_turmuk_ctg_beta3"

================================================================
Forwards output of this plugin, and the matching veto event log:
================================================================

OnMapVetoStageUpdate: 1 (VETO_STAGE_COIN_FLIP) ---> [MAP PICK] Flipping coin... Team NSF vetoes first.

OnMapVetoStageUpdate: 2 (VETO_STAGE_FIRST_TEAM_BAN)
OnMapVetoPick: 2, 3, 0 (VETO_STAGE_FIRST_TEAM_BAN, TEAM_NSF, map index 0) ---> [VETO] Team NSF vetoes map: nt_ballistrade_ctg

OnMapVetoStageUpdate: 3 (VETO_STAGE_SECOND_TEAM_BAN)
OnMapVetoPick: 3, 2, 1 (VETO_STAGE_SECOND_TEAM_BAN, TEAM_JINRAI, map index 1) ---> [VETO] Team Jinrai vetoes map: nt_shipment_ctg_comp_rc1

OnMapVetoStageUpdate: 4 (VETO_STAGE_SECOND_TEAM_PICK)
OnMapVetoPick: 4, 2, 3 (VETO_STAGE_SECOND_TEAM_PICK, TEAM_JINRAI, map index 3) ---> [PICK] Team Jinrai picks map: nt_oliostain_ctg_b3

OnMapVetoStageUpdate: 5 (VETO_STAGE_FIRST_TEAM_PICK)
OnMapVetoPick: 5, 3, 6 (VETO_STAGE_FIRST_TEAM_PICK, TEAM_NSF, map index 6) ---> [PICK] Team NSF picks map: nt_turmuk_ctg_beta3

OnMapVetoStageUpdate: 6 (VETO_STAGE_RANDOM_THIRD_MAP)
OnMapVetoPick: 6, 1, 4 (VETO_STAGE_RANDOM_THIRD_MAP, TEAM_SPECTATOR, map index 4) ---> [PICK] Third map is: nt_rise_ctg

======================
And final veto output:
======================

== MAP PICK RESULTS ==
  - Map 1: nt_oliostain_ctg_b3 (NSF pick)
  - Map 2: nt_turmuk_ctg_beta3 (Jinrai pick)
  - Map 3: nt_rise_ctg (random pick)

=========================================
After which the veto goes inactive again:
=========================================

OnMapVetoStageUpdate: 0 (VETO_STAGE_INACTIVE)
*/

public void OnAllPluginsLoaded()
{
    // Amount of maps available in the competitive veto/picks pool total.
    int num_maps = CompetitiveVetos_GetVetoMapPoolSize();

    // Buffer to store all of the map names.
    char[][] maps = new char[num_maps][PLATFORM_MAX_PATH];

    // Actually get the maps.
    for (int map_index = 0; map_index < num_maps; ++map_index) {
        // Maps are 0 indexed, so first map is map number 0, etc.
        int num_chars_written = CompetitiveVetos_GetNameOfMapPoolMap(map_index,
            maps[map_index], PLATFORM_MAX_PATH);

        if (num_chars_written == 0) {
            SetFailState("Failed to get map name");
        }
        else {
            PrintToServer("Map %d: \"%s\"", map_index, maps[map_index]);
        }
    }
}

public void OnMapVetoStageUpdate(int new_veto_stage)
{
    PrintToServer("OnMapVetoStageUpdate: %d", new_veto_stage);
}

public void OnMapVetoPick(int current_veto_stage, int vetoing_team, const char[] map_name)
{
    PrintToServer("OnMapVetoPick: %d, %d, \"%s\"", current_veto_stage, vetoing_team, map_name);
}
