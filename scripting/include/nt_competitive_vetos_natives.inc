#if defined _NT_COMPETITIVE_VETOS_NATIVES_INC_
    #endinput
#endif

#define _NT_COMPETITIVE_VETOS_NATIVES_INC_

// For the VetoStage enum, see the include file nt_competitive_vetos_enum.inc.

/************
 *  NATIVES *
 ************/

/**
 * Whether a veto is currently in progress.
 *
 * @param1 first_veto_team    Out value will be passed into this optional param by reference.
 *                            The value can be one of:
 *                                If this native returns true:
 *                                    The value passed will be the team index of the coin flip winner (TEAM_JINRAI or TEAM_NSF), or 0 if the coin flip hasn't finished yet.
 *                                Else, if this native returns false:
 *                                    The value passed will hold no information.
 * @return                    True if veto is currently active, false otherwise.
 */
native bool CompetitiveVetos_IsVetoActive(int& first_veto_team = 0);

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
 * you can ensure the request will be in bounds by querying
 * n = CompetitiveVetos_GetVetoMapPoolSize() to determine a valid range of
 * ("0 to n"), and then providing map_index within that range to this call,
 * assuming that n was indeed > 0.
 *
 * @param1 map_index          Index of the map name to fetch.
 * @param2 out_buffer         Char array to store the fetched map into. Will be passed to by reference.
 * @param3 max_len            Maximum buffer size of out_buffer. It is recommended to provide a buffer of size PLATFORM_MAX_PATH.
 * @return                    Number of characters written in the out_buffer (including null terminator), or 0 if failed to write.
 */
native int CompetitiveVetos_GetNameOfMapPoolMap(int map_index, char[] out_buffer, int max_len);

/*************
 *  FORWARDS *
 *************/

/* Called whenever the veto state changes according to the enum above.
*    public void OnMapVetoStageUpdate(VetoStage new_veto_stage, int param2);
*      - new_veto_stage:          VetoStage enum that was entered when this forward fired.
*      - param2:                  If (new_veto_stage == VETO_STAGE_COIN_FLIP_RESULT): Will contain the team index that vetoes first.
                                  Else, this value will not represent any information, in which case it will hold the value -1.
*/

/* public void OnMapVetoPick(VetoStage current_veto_stage, int vetoing_team, const char[] map_name);
*    Called whenever a team decides on one of their pick/ban.
*      - current_veto_stage:      VetoStage enum for determining what kind of pick this was.
*
*      - vetoing_team:            Which team did this pick.
*                                 TEAM_JINRAI or TEAM_NSF (or TEAM_SPECTATOR for the random pick),
*                                 as teams are defined in neotokyo.inc.
*
*      - map_name:                Name of the map being picked or vetoed.
*                                 Maximum length of the const char[] is PLATFORM_MAX_PATH.
*/
