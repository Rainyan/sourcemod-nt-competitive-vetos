#pragma semicolon 1

#include <sourcemod>

#include <nt_competitive_vetos_natives>

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