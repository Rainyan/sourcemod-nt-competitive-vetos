#if defined _NT_COMPETITIVE_VETOS_NATIVES_INC_
    #endinput
#endif

#define _NT_COMPETITIVE_VETOS_NATIVES_INC_

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
 * at the selected index. Note that the indices are 0 indexed, so the first
 * map will be at index 0, second map at index 1, and so on.
 *
 * Requesting an index that is out of bounds will fire ThrowNativeError;
 * you can ensure the request is in bounds with CompetitiveVetos_GetVetoMapPoolSize().
 *
 * @param1 map_index          Index of the map name to fetch.
 * @param2 out_buffer         Char array to store the fetched map into.
 * @param3 max_len            Maximum buffer size of out_buffer.
 * @return                    Number of characters written in the out_buffer, or 0 if failed to write.
 */
native int CompetitiveVetos_GetNameOfMapPoolMap(int map_index, char[] out_buffer, int max_len);
