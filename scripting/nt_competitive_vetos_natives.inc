#if defined _NT_COMPETITIVE_VETOS_NATIVES_INC_
    #endinput
#endif

#define _NT_COMPETITIVE_VETOS_NATIVES_INC_

/************
 *  NATIVES *
 ************/

/**
 * Whether a veto is currently in progress.
 *
 * @return                    True if veto is currently active, false otherwise.
 */
native bool CompetitiveVetos_IsVetoActive();

/**
 * Returns the number of maps in the current competitive veto/picks map pool.
 *
 * @return                    Number of maps.
 */
native int CompetitiveVetos_GetVetoMapPoolSize();

/**
 * Returns the name of a map in the current competitive veto/picks map pool
 * at the selected index by reference.
 *
 * Note that the indices are 0 indexed, so the first
 * map will be at index 0, second map at index 1, and so on.
 *
 * Requesting an index that is out of bounds will fire ThrowNativeError;
 * you can ensure the request will be in bounds with CompetitiveVetos_GetVetoMapPoolSize()
 * before calling this.
 *
 * @param1 map_index          Index of the map name to fetch.
 * @param2 out_buffer         Char array to store the fetched map into. Will be passed by reference.
 * @param3 max_len            Maximum buffer size of out_buffer.
 * @return                    Number of characters written in the out_buffer, or 0 if failed to write.
 */
native int CompetitiveVetos_GetNameOfMapPoolMap(int map_index, char[] out_buffer, int max_len);

/*************
 *  FORWARDS *
 *************/

/*
// Stages used in the plugin forwards below.
enum VetoStage {
    VETO_STAGE_INACTIVE = 0,         // - Vetoing is not happening at all currently (or was finished)
    VETO_STAGE_COIN_FLIP,            // - Doing a coin flip to decide who vetoes first
    VETO_STAGE_FIRST_TEAM_BAN,       // - Currently deciding on the first veto (Team 1)
    VETO_STAGE_SECOND_TEAM_BAN,      // - Currently deciding on the second veto (Team 2)
    VETO_STAGE_SECOND_TEAM_PICK,     // - Currently deciding on the first pick (Team 2)
    VETO_STAGE_FIRST_TEAM_PICK,      // - Currently deciding on the second pick (Team 2)
    VETO_STAGE_RANDOM_THIRD_MAP,     // - Currently deciding on the third random map.
                                     //   VETO_STAGE_RANDOM_THIRD_MAP will be followed
                                     //   by VETO_STAGE_INACTIVE upon veto completion.
    NUM_STAGES                       // - Unused
};
*/

/* Called whenever the veto state changes according to the enum above.
*    public void OnMapVetoStageUpdate(int new_veto_stage);
*      - new_veto_stage:          VetoStage enum that was entered when this forward fired.
*/

/* public void OnMapVetoPick(int current_veto_stage, int vetoing_team, int vetoed_map_index);
*    Called whenever a team decides on one of their pick/ban.
*      - current_veto_stage:      VetoStage enum for determining what kind of pick this was.
*
*      - vetoing_team:            Which team did this pick.
*                                 TEAM_JINRAI or TEAM_NSF (or TEAM_SPECTATOR for the random pick),
*                                 as teams are defined in neotokyo.inc.
*
*      - vetoed_map_index:        Index of the map being picked or vetoed. Same indices
*                                 as returned by the natives CompetitiveVetos_GetVetoMapPoolSize()
*                                 and CompetitiveVetos_GetNameOfMapPoolMap(...).
*/
