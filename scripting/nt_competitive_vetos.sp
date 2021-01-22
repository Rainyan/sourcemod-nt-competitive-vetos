#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#include <neotokyo>

#define PLUGIN_VERSION "0.3"

#define NEO_MAX_PLAYERS 32
#define MAX_CUSTOM_TEAM_NAME_LEN 64

static const String:g_sTag[] = "[MAP PICK]";
static const String:g_sSound_Veto[] = "ui/buttonrollover.wav";
static const String:g_sSound_Pick[] = "ui/buttonclick.wav";
static const String:g_sSound_Results[] = "player/CPcaptured.wav";

#define MAP_VETO_TITLE "MAP PICK"
#define INVALID_MAP_ARR_INDEX -1

// Debug flag for forcing all the vetos on the Jinrai team side.
//#define DEBUG_ALL_VETOS_BY_JINRAI

enum VetoStage {
	VETO_STAGE_FIRST_TEAM_BAN = 0,
	VETO_STAGE_SECOND_TEAM_BAN,
	VETO_STAGE_SECOND_TEAM_PICK,
	VETO_STAGE_FIRST_TEAM_PICK,
	VETO_STAGE_RANDOM_THIRD_MAP,
	
	NUM_STAGES
};

// TODO: Move map pool out of code into a config file, and allow any sized map pool.
#define NUM_MAPS 7
static const String:_maps[NUM_MAPS][] = {
	"nt_ballistrade_ctg",
	"nt_shipment_ctg_comp_rc1",
	"nt_snowfall_ctg_b3",
	"nt_oliostain_ctg_b3",
	"nt_rise_ctg",
	"nt_threadplate_ctg",
	"nt_turmuk_ctg_beta3"
};
static int _is_vetoed_by[NUM_MAPS];
static int _is_picked_by[NUM_MAPS];

static bool _is_veto_active;
static bool _wants_to_start_veto_jinrai;
static bool _wants_to_start_veto_nsf;

static VetoStage _veto_stage;

static int _first_veto_team;
static int _pending_map_pick_nomination_for_vote;

ConVar g_hCvar_JinraiName = null;
ConVar g_hCvar_NsfName = null;

public Plugin myinfo = {
	name = "NT Tournament Map Picker",
	description = "Helper plugin for doing tournament map picks/vetos.",
	author = "Rain",
	version = PLUGIN_VERSION,
	url = "https://github.com/Rainyan/sourcemod-nt-competitive-vetos"
};

// Native from plugin: nt_competitive.
native bool Competitive_IsLive();

public void OnPluginStart()
{
	// TODO: Currently using a basic Panel approach for some of the maps listing stuff.
	// Refactoring the Panels to Menus would provide pagination support for larger map pools.
#if NUM_MAPS >= 9
#error Pagination of >=9 maps pool is currently unsupported. See code comment at this error for more info.
#endif
	
	CreateConVar("sm_nt_tournament_map_picker_version", PLUGIN_VERSION, "NT Tournament Map Picker plugin version.", FCVAR_DONTRECORD);
	
	RegAdminCmd("sm_vetofirst", Cmd_StartVetoFirst, ADMFLAG_GENERIC, "Admin command to select which team should pick first (skips the coin flip).");
	
	RegConsoleCmd("sm_veto", Cmd_StartVeto, "Start the map picks/vetos.");
	RegConsoleCmd("sm_unveto", Cmd_CancelVeto, "Start the map picks/vetos.");
	
	RegAdminCmd("sm_resetveto", Cmd_ResetVeto, ADMFLAG_GENERIC, "Admin command to reset a veto in progress.");
}

public void OnAllPluginsLoaded()
{
	g_hCvar_JinraiName = FindConVar("sm_competitive_jinrai_name");
	g_hCvar_NsfName = FindConVar("sm_competitive_nsf_name");
	if (g_hCvar_JinraiName == null || g_hCvar_NsfName == null) {
		SetFailState("Failed to look up nt_competitive team name cvars. Is nt_competitive plugin enabled?");
	}
}

public void OnMapStart()
{
	if (!PrecacheSound(g_sSound_Veto)) {
		SetFailState("Failed to precache sound: \"%s\"", g_sSound_Veto);
	}
	else if (!PrecacheSound(g_sSound_Pick)) {
		SetFailState("Failed to precache sound: \"%s\"", g_sSound_Pick);
	}
	else if (!PrecacheSound(g_sSound_Results)) {
		SetFailState("Failed to precache sound: \"%s\"", g_sSound_Results);
	}
	
	ClearVeto();
}

public Action Cmd_ResetVeto(int client, int argc)
{
	if (_is_veto_active) {
		PrintToChatAll("%s Veto has been reset by admin.", g_sTag);
		PrintToConsoleAll("%s Veto has been reset by admin.", g_sTag);
		LogToGame("%s Veto has been reset by admin.", g_sTag);
	}
	else {
		ReplyToCommand(client, "%s No veto was active. Will reset veto internals, regardless.", g_sTag);
	}
	
	ClearVeto();	
	return Plugin_Handled;
}

void ClearVeto()
{
	for (int i = 0; i < NUM_MAPS; ++i) {
		_is_vetoed_by[i] = 0;
		_is_picked_by[i] = 0;
	}
	
	_is_veto_active = false;
	_wants_to_start_veto_jinrai = false;
	_wants_to_start_veto_nsf = false;
	
	_veto_stage = VETO_STAGE_FIRST_TEAM_BAN;
	
	_first_veto_team = 0;
	_pending_map_pick_nomination_for_vote = INVALID_MAP_ARR_INDEX;
}

public Action Cmd_StartVeto(int client, int argc)
{
	if (client == 0) {
		ReplyToCommand(client, "%s This command cannot be executed by the server.", g_sTag);
		return Plugin_Handled;
	}
	else if (_is_veto_active) {
		ReplyToCommand(client, "%s Map picks/veto is already active.", g_sTag);
		return Plugin_Handled;
	}
	
	int team = GetClientTeam(client);
	
	if (team <= TEAM_SPECTATOR) {
		ReplyToCommand(client, "%s Picks can only be initiated by the players.", g_sTag);
		return Plugin_Handled;
	}
	else if (IsPlayingTeamEmpty()) {
		ReplyToCommand(client, "%s Both teams need to have players in them to start the map picks.", g_sTag);
		return Plugin_Handled;
	}
	else if (Competitive_IsLive()) {
		ReplyToCommand(client, "%s Cannot start the veto when the match is live.", g_sTag);
		return Plugin_Handled;
	}
	
	char team_name[MAX_CUSTOM_TEAM_NAME_LEN];
	GetCompetitiveTeamName(team, team_name, sizeof(team_name));
	
	if (team == TEAM_JINRAI) {
		if (_wants_to_start_veto_jinrai) {
			ReplyToCommand(client, "%s Already ready for veto. Please use !unveto if you wish to cancel.", g_sTag);
			return Plugin_Handled;
		}
		else {
			_wants_to_start_veto_jinrai = true;
			PrintToChatAll("%s Team %s is ready to start map picks/veto.", g_sTag, team_name);
		}
	}
	else {
		if (_wants_to_start_veto_nsf) {
			ReplyToCommand(client, "%s Already ready for veto. Please use !unveto if you wish to cancel.", g_sTag);
			return Plugin_Handled;
		}
		else {
			_wants_to_start_veto_nsf = true;
			PrintToChatAll("%s Team %s is ready to start map picks/veto.", g_sTag, team_name);
		}
	}
	
	if (!CheckIfReadyToStartVeto()) {
		char other_team_name[MAX_CUSTOM_TEAM_NAME_LEN];
		GetCompetitiveTeamName(GetOpposingTeam(team), other_team_name, sizeof(other_team_name));
		
		PrintToChatAll("%s Waiting for team %s to confirm with !veto.", g_sTag, other_team_name);
	}
	
	return Plugin_Handled;
}

public Action Cmd_CancelVeto(int client, int argc)
{
	if (client == 0) {
		ReplyToCommand(client, "%s This command cannot be executed by the server.", g_sTag);
		return Plugin_Handled;
	}
	else if (_is_veto_active) {
		ReplyToCommand(client, "%s Map picks/veto is already active.", g_sTag);
		return Plugin_Handled;
	}
	
	int team = GetClientTeam(client);
	
	if (team <= TEAM_SPECTATOR) {
		ReplyToCommand(client, "%s Picks can only be initiated by the players.", g_sTag);
		return Plugin_Handled;
	}
	else if (Competitive_IsLive()) {
		ReplyToCommand(client, "%s Match is already live; cannot modify a veto right now.", g_sTag);
		return Plugin_Handled;
	}
	
	char team_name[MAX_CUSTOM_TEAM_NAME_LEN];
	GetCompetitiveTeamName(team, team_name, sizeof(team_name));
	
	if (team == TEAM_JINRAI) {
		if (!_wants_to_start_veto_jinrai) {
			ReplyToCommand(client, "%s Already not ready for veto. Please use !veto if you wish to start a veto.", g_sTag);
			return Plugin_Handled;
		}
		else {
			_wants_to_start_veto_jinrai = false;
			PrintToChatAll("%s Team %s is no longer ready for !veto.", g_sTag, team_name);
		}
	}
	else {
		if (!_wants_to_start_veto_nsf) {
			ReplyToCommand(client, "%s Already not ready for veto. Please use !veto if you wish to start a veto.", g_sTag);
			return Plugin_Handled;
		}
		else {
			_wants_to_start_veto_nsf = false;
			PrintToChatAll("%s Team %s is no longer ready for !veto.", g_sTag, team_name);
		}
	}
	
	return Plugin_Handled;
}

public Action Cmd_StartVetoFirst(int client, int argc)
{
	if (_is_veto_active) {
		ReplyToCommand(client, "%s Picks already active. Use !resetveto first.", g_sTag);
		return Plugin_Handled;
	}
	else if (IsPlayingTeamEmpty()) {
		ReplyToCommand(client, "%s Both teams need to have players in them to start the map picks.", g_sTag);
		return Plugin_Handled;
	}
	
	char cmd_name[32];
	GetCmdArg(0, cmd_name, sizeof(cmd_name));
	
	if (argc != 1) {
		ReplyToCommand(client, "%s Usage: %s jinrai/nsf (don't use a team custom name)", g_sTag, cmd_name);
		return Plugin_Handled;
	}
	else if (Competitive_IsLive()) {
		ReplyToCommand(client, "%s Cannot start the veto when the match is live.", g_sTag);
		return Plugin_Handled;
	}
	
	char team_name[7]; // "Jinrai" + '\0'
	GetCmdArg(1, team_name, sizeof(team_name));
	int team_that_goes_first;
	if (StrEqual(team_name, "Jinrai", false)) {
		team_that_goes_first = TEAM_JINRAI;
	}
	else if (StrEqual(team_name, "NSF", false)) {
		team_that_goes_first = TEAM_NSF;
	}
	
	if (team_that_goes_first != TEAM_JINRAI && team_that_goes_first != TEAM_NSF) {
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
	if (_is_veto_active || !_wants_to_start_veto_jinrai || !_wants_to_start_veto_nsf) {
		return false;
	}
	StartNewVeto();
	return true;
}

void StartNewVeto(int team_goes_first = 0)
{
	if (_is_veto_active) {
		ThrowError("Called while another veto is already active");
	}
	else if (ResetPicksIfShould()) {
		return;
	}
	
	ClearVeto();
	_is_veto_active = true;
	
	PrintToChatAll("%s Starting map picks/veto...", g_sTag);
	EmitSoundToAll(g_sSound_Results);
	
	if (team_goes_first == 0) {
		DoCoinFlip();
	}
	else {
		_first_veto_team = team_goes_first;
		CreateTimer(0.1, Timer_StartVeto, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

void DoCoinFlip(const int coinflip_stage = 0)
{	
	if (ResetPicksIfShould()) {
		return;
	}
	
	Panel panel = new Panel();
	panel.SetTitle(MAP_VETO_TITLE);
	
	// Characters to represent the "coin flip" spinning around, for some appropriate suspense.
	char coinflip_anim[][] = { "-", "\\", "|", "/" };
	// How many 180 coin flips for the full animation, ie. 3 = 1.5 full rotations.
#define NUM_COINFLIP_ANIMATION_HALF_ROTATIONS 3
	
	if (coinflip_stage < sizeof(coinflip_anim) * NUM_COINFLIP_ANIMATION_HALF_ROTATIONS) {
		char text[19];
		Format(text, sizeof(text), "Flipping coin... %s", coinflip_anim[coinflip_stage % sizeof(coinflip_anim)]);
		panel.DrawText(" ");
		panel.DrawText(text);
		
		CreateTimer(0.33, Timer_CoinFlip, coinflip_stage + 1, TIMER_FLAG_NO_MAPCHANGE);
	}
	else {
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
		
#define COINFLIP_RESULTS_SHOW_DURATION 5
		CreateTimer(COINFLIP_RESULTS_SHOW_DURATION * 1.0, Timer_StartVeto, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	for (int client = 1; client <= MaxClients; ++client) {
		if (!IsClientInGame(client) || IsFakeClient(client)) {
			continue;
		}
		panel.Send(client, MenuHandler_DoNothing, COINFLIP_RESULTS_SHOW_DURATION);
	}
	delete panel;
}

public Action Timer_StartVeto(Handle timer)
{
	if (ResetPicksIfShould()) {
		return Plugin_Stop;
	}
	
	CreateTimer(1.0, Timer_ReShowMenu, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Stop;
}

public Action Timer_ReShowMenu(Handle timer)
{
	if (!_is_veto_active) {
		return Plugin_Stop;
	}
	DoVeto();
	return Plugin_Continue;
}

void DoVeto()
{
	if (_veto_stage == NUM_STAGES) {
		ThrowError("Invalid veto stage (%d)", _veto_stage);
	}
	
	if (ResetPicksIfShould()) {
		return;
	}
	
	if (_pending_map_pick_nomination_for_vote != INVALID_MAP_ARR_INDEX) {
		return;
	}
	
	if (_veto_stage == VETO_STAGE_RANDOM_THIRD_MAP) {
		int maps[3];
		int num_maps = 0;
		for (int i = 0; i < NUM_MAPS; ++i) {
			if (_is_picked_by[i] == 0 && _is_vetoed_by[i] == 0) {
				maps[num_maps++] = i;
			}
		}
		if (num_maps == 0) {
			ThrowError("Failed to pick random map");
		}
		SetRandomSeed(GetTime());
		int third_map = maps[GetRandomInt(0, num_maps - 1)];
		_is_picked_by[third_map] = TEAM_SPECTATOR;
		
		PrintToChatAll("[PICK] Third map is: %s", _maps[third_map]);
		PrintToConsoleAll("[PICK] Third map is: %s", _maps[third_map]);
		LogToGame("[PICK] Third map is: %s", _maps[third_map]);
		
		AnnounceMaps();
		ClearVeto();
		return;
	}
	
	int picking_team = GetPickingTeam();
#if defined DEBUG_ALL_VETOS_BY_JINRAI
	picking_team = TEAM_JINRAI;
#endif
	
	if (picking_team != TEAM_JINRAI && picking_team != TEAM_NSF) {
		ThrowError("Invalid team: %d", picking_team);
	}
	
	Menu picker_menu = new Menu(MenuHandler_DoPick);
	// We're re-drawing this Menu anyway so that client can't accidentally
	// lock themselves out of the picks, but removing the exit button
	// to make the menu cleaner.
	// TODO 1: make sure this property works with NT.
	// TODO 2: "No vote" option, and make it actually a vote.
	// Have to look into working with other SM votes for edge cases, too:
	//   MenuAction_End --> MenuEnd_VotingDone, etc.
	// See: https://sm.alliedmods.net/new-api/menus/__raw
	picker_menu.ExitButton = false;
	
	Panel spec_panel = new Panel();
	spec_panel.SetTitle(MAP_VETO_TITLE);
	spec_panel.DrawText(" ");
	
	char jinrai_name[MAX_CUSTOM_TEAM_NAME_LEN];
	char nsf_name[MAX_CUSTOM_TEAM_NAME_LEN];
	GetCompetitiveTeamName(TEAM_JINRAI, jinrai_name, sizeof(jinrai_name));
	GetCompetitiveTeamName(TEAM_NSF, nsf_name, sizeof(nsf_name));
	
	bool is_ban_stage = (_veto_stage == VETO_STAGE_FIRST_TEAM_BAN ||
		_veto_stage == VETO_STAGE_SECOND_TEAM_BAN);
	
	picker_menu.SetTitle("Your team's map %s:", is_ban_stage ? "VETO" : "PICK");
	
	spec_panel.DrawText(is_ban_stage ? "Waiting for veto by:" : "Waiting for pick by:");
	spec_panel.DrawText((picking_team == TEAM_JINRAI) ? jinrai_name : nsf_name);
	spec_panel.DrawText(" ");
	
	char buffer[PLATFORM_MAX_PATH + MAX_CUSTOM_TEAM_NAME_LEN + 12];
	for (int i = 0; i < sizeof(_maps); ++i) {
		if (_is_vetoed_by[i] == 0 && _is_picked_by[i] == 0) {
			picker_menu.AddItem(_maps[i], _maps[i], ITEMDRAW_DEFAULT);
			spec_panel.DrawText(_maps[i]);
		}
		else if (_is_vetoed_by[i] != 0) {
			Format(buffer, sizeof(buffer), "%s (VETO of %s)", _maps[i],
				(_is_vetoed_by[i] == TEAM_JINRAI) ? jinrai_name : nsf_name);
			picker_menu.AddItem("null", buffer, ITEMDRAW_DISABLED);
			spec_panel.DrawText(buffer);
		}
		else if (_is_picked_by[i] != 0) {
			Format(buffer, sizeof(buffer), "%s (PICK of %s)", _maps[i],
				(_is_picked_by[i] == TEAM_JINRAI) ? jinrai_name : nsf_name);
			picker_menu.AddItem("null", buffer, ITEMDRAW_DISABLED);
			spec_panel.DrawText(buffer);
		}
	}
	
	for (int client = 1; client <= MaxClients; ++client) {
		if (!IsClientInGame(client) || IsFakeClient(client)) {
			continue;
		}
		
		if (GetClientTeam(client) == picking_team) {
			picker_menu.Display(client, 2);
		}
		else {
			spec_panel.Send(client, MenuHandler_DoNothing, 2);
		}
	}
	
	delete spec_panel;
}

public Action Timer_CoinFlip(Handle timer, int coinflip_stage)
{
	if (!_is_veto_active || ResetPicksIfShould()) {
		return Plugin_Stop;
	}
	DoCoinFlip(coinflip_stage);
	return Plugin_Stop;
}

// Assuming that anyone using this callback will manage their Panel/Menu handle memory themselves.
public int MenuHandler_DoNothing(Menu menu, MenuAction action, int param1, int param2)
{
}

// Note that the callback params are guaranteed to actually represent client & selection
// only in some MenuActions; assuming (action == MenuAction_Select) in this context.
public int MenuHandler_DoPick(Menu menu, MenuAction action, int client, int selection)
{	
	if (action == MenuAction_End) {
		delete menu;
	}
	
	bool veto_was_cancelled = ResetPicksIfShould();
	
	if (!veto_was_cancelled && client > 0 && client <= MaxClients &&
		IsClientInGame(client) && !IsFakeClient(client) && action == MenuAction_Select)
	{
		int client_team = GetClientTeam(client);
		if (client_team == GetPickingTeam()) {
			char jinrai_name[MAX_CUSTOM_TEAM_NAME_LEN];
			char nsf_name[MAX_CUSTOM_TEAM_NAME_LEN];
			g_hCvar_JinraiName.GetString(jinrai_name, sizeof(jinrai_name));
			g_hCvar_NsfName.GetString(nsf_name, sizeof(nsf_name));
			
			char chosen_map[PLATFORM_MAX_PATH];
			if (!menu.GetItem(selection, chosen_map, sizeof(chosen_map))) {
				ThrowError("Failed to retrieve selection (%d)", selection);
			}
			int map_index = GetChosenMapIndex(chosen_map);
			if (map_index == INVALID_MAP_ARR_INDEX) {
				ThrowError("Couldn't find map: \"%s\"", chosen_map);
			}
			
			ConfirmSoloMapPick(client, client_team, map_index, chosen_map);
			
#if(0)
			char client_name[MAX_NAME_LENGTH];
			GetClientName(client, client_name, sizeof(client_name));
			
			if (_veto_stage == VETO_STAGE_FIRST_TEAM_BAN || _veto_stage == VETO_STAGE_SECOND_TEAM_BAN) {
				_is_vetoed_by[map_index] = client_team;
				
				int other_clients[NEO_MAX_PLAYERS + 1];
				int num_other_clients = GetClientsExceptOne(client, other_clients, sizeof(other_clients));
				EmitSound(other_clients, num_other_clients, g_sSound_Veto);
				
				PrintToChatAll("[VETO] Team %s (player %s) vetoes map: %s",
					(client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, client_name, chosen_map);
				PrintToConsoleAll("[VETO] Team %s (player %s) vetoes map: %s",
					(client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, client_name, chosen_map);
				LogToGame("[VETO] Team %s (player %s) vetoes map: %s",
					(client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, client_name, chosen_map);
			}
			else if (_veto_stage == VETO_STAGE_FIRST_TEAM_PICK || _veto_stage == VETO_STAGE_SECOND_TEAM_PICK) {
				_is_picked_by[map_index] = client_team;
				
				int other_clients[NEO_MAX_PLAYERS + 1];
				int num_other_clients = GetClientsExceptOne(client, other_clients, sizeof(other_clients));
				EmitSound(other_clients, num_other_clients, g_sSound_Pick);
				
				PrintToChatAll("[PICK] Team %s (player %s) picks map: %s",
					(client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, client_name, chosen_map);
				PrintToConsoleAll("[PICK] Team %s (player %s) picks map: %s",
					(client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, client_name, chosen_map);
				LogToGame("[PICK] Team %s (player %s) picks map: %s",
					(client_team == TEAM_JINRAI) ? jinrai_name : nsf_name, client_name, chosen_map);
			}
			else {
				ThrowError("Unexpected veto stage: %d", _veto_stage);
			}
			++_veto_stage;
			DoVeto();
#endif
		}
	}
}

void ConfirmSoloMapPick(int client, int team, int map_pick, const char[] map_name)
{
	if (team != TEAM_JINRAI && team != TEAM_NSF) {
		ThrowError("Unexpected team: %d", team);
	}
	else if (map_pick < 0 || map_pick >= sizeof(_maps)) {
		ThrowError("Unexpected map pick index: %d", map_pick);
	}
	
	_pending_map_pick_nomination_for_vote = map_pick;
	
	char client_name[MAX_NAME_LENGTH];
	GetClientName(client, client_name, sizeof(client_name));
	
	Menu vote_menu = new Menu(MenuHandler_ConfirmSoloMapPick, MenuAction_VoteCancel);
	vote_menu.ExitButton = false;
	vote_menu.VoteResultCallback = VoteHandler_ConfirmSoloMapPick;
	
	bool is_ban_stage = (_veto_stage == VETO_STAGE_FIRST_TEAM_BAN ||
		_veto_stage == VETO_STAGE_SECOND_TEAM_BAN);
	
	vote_menu.SetTitle("%s wants to use team %s for map: %s (need at least 50%c consensus)",
		client_name,
		is_ban_stage ? "VETO" : "PICK",
		map_name,
		'%'); // Note: the panel formats text differently, so need to use %c -> '%' for percentages here.
	
	vote_menu.AddItem("yes", "Vote yes", ITEMDRAW_DEFAULT);
	vote_menu.AddItem("no", "Vote no", ITEMDRAW_DEFAULT);
	
	int voters[NEO_MAX_PLAYERS];
	int num_voters;
	for (int iter_client = 1; iter_client <= MaxClients; ++iter_client) {
		if (!IsClientInGame(iter_client) || IsFakeClient(iter_client)) {
			continue;
		}
		if (GetClientTeam(iter_client) != team) {
			continue;
		}
		voters[num_voters++] = iter_client;
	}
	
	if (IsVoteInProgress()) {
		CancelVote();
		PrintToChatAll("%s Cancelling existing vote because veto voting is currently active.", g_sTag);
	}
	vote_menu.DisplayVote(voters, num_voters, MENU_TIME_FOREVER);
}

public int MenuHandler_ConfirmSoloMapPick(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End) {
		delete menu;
	}
	// Veto was interrupted for some reason. Return to the veto stage to try again.
	else if (action == MenuAction_VoteCancel) {
		// If this already equaled INVALID_MAP_ARR_INDEX, the vote has already been cancelled by this plugin (admin reset, etc.)
		if (_pending_map_pick_nomination_for_vote != INVALID_MAP_ARR_INDEX) {
			_pending_map_pick_nomination_for_vote = INVALID_MAP_ARR_INDEX;
			DoVeto();
		}
	}
}

public void VoteHandler_ConfirmSoloMapPick(Menu menu, int num_votes, int num_clients,
	const int[][] client_info, int num_items, const int[][] item_info)
{
	// Vote has been reset by this plugin (admin reset, etc.)
	if (_pending_map_pick_nomination_for_vote == INVALID_MAP_ARR_INDEX) {
		return;
	}
	
	// Nobody voted yes/no, don't do anything yet.
	if (num_votes == 0) {
		_pending_map_pick_nomination_for_vote = INVALID_MAP_ARR_INDEX;
		DoVeto();
		return;
	}
	
	int num_yes_votes;
	int num_no_votes;
	int voting_team;
	
	for (int i = 0; i < num_clients; ++i) {
		if (voting_team == 0) {
			voting_team = GetClientTeam(client_info[i][0]);
			if (voting_team != TEAM_JINRAI && voting_team != TEAM_NSF) {
				ThrowError("Failed to get a valid voting team (%d)", voting_team);
			}
		}
		
		if (client_info[i][1] == 0) {
			++num_yes_votes;
		}
		else {
			++num_no_votes;
		}
	}
	
	if (num_yes_votes >= num_no_votes) {
		char jinrai_name[MAX_CUSTOM_TEAM_NAME_LEN];
		char nsf_name[MAX_CUSTOM_TEAM_NAME_LEN];
		GetCompetitiveTeamName(TEAM_JINRAI, jinrai_name, sizeof(jinrai_name));
		GetCompetitiveTeamName(TEAM_NSF, nsf_name, sizeof(nsf_name));
		
		if (_veto_stage == VETO_STAGE_FIRST_TEAM_BAN || _veto_stage == VETO_STAGE_SECOND_TEAM_BAN) {
			_is_vetoed_by[_pending_map_pick_nomination_for_vote] = voting_team;
			
			EmitSoundToAll(g_sSound_Veto);
			
			PrintToAllExceptTeam(voting_team, "[VETO] Team %s vetoes map: %s",
				(voting_team == TEAM_JINRAI) ? jinrai_name : nsf_name,
				_maps[_pending_map_pick_nomination_for_vote]);
			LogToGame("[VETO] Team %s vetoes map: %s",
				(voting_team == TEAM_JINRAI) ? jinrai_name : nsf_name, _maps[_pending_map_pick_nomination_for_vote]);
		}
		else if (_veto_stage == VETO_STAGE_FIRST_TEAM_PICK || _veto_stage == VETO_STAGE_SECOND_TEAM_PICK) {
			_is_picked_by[_pending_map_pick_nomination_for_vote] = voting_team;
			
			EmitSoundToAll(g_sSound_Pick);
			
			PrintToAllExceptTeam(voting_team, "[PICK] Team %s picks map: %s",
				(voting_team == TEAM_JINRAI) ? jinrai_name : nsf_name,
				_maps[_pending_map_pick_nomination_for_vote]);
			LogToGame("[PICK] Team %s picks map: %s",
				(voting_team == TEAM_JINRAI) ? jinrai_name : nsf_name, _maps[_pending_map_pick_nomination_for_vote]);
		}
		else {
			ThrowError("Unexpected veto stage: %d", _veto_stage);
		}
		
		PrintToTeam(voting_team, "%s Your team %sd map %s (%d%s yes votes of %d votes total).",
			(_veto_stage == VETO_STAGE_FIRST_TEAM_BAN || _veto_stage == VETO_STAGE_SECOND_TEAM_BAN) ? "[VETO]" : "[PICK]",
			(_veto_stage == VETO_STAGE_FIRST_TEAM_BAN || _veto_stage == VETO_STAGE_SECOND_TEAM_BAN) ? "vetoe" : "picke",
			_maps[_pending_map_pick_nomination_for_vote],
			(num_yes_votes == 0) ? 100 : ((1 - (num_no_votes / num_yes_votes)) * 100),
			"%%",
			num_votes);
		
		++_veto_stage;
	}
	else {
		PrintToTeam(voting_team, "%s Need at least 50%s of yes votes (got %d%s).",
			g_sTag,
			"%%",
			(num_no_votes == 0) ? 0 : (num_yes_votes / num_no_votes),
			"%%");
	}
	
	_pending_map_pick_nomination_for_vote = INVALID_MAP_ARR_INDEX;
	DoVeto();
}

int GetChosenMapIndex(const char[] map)
{
	for (int i = 0; i < NUM_MAPS; ++i) {
		if (StrEqual(_maps[i], map)) {
			return i;
		}
	}
	return INVALID_MAP_ARR_INDEX;
}

int GetOpposingTeam(int team)
{
#if defined DEBUG_ALL_VETOS_BY_JINRAI
	return TEAM_JINRAI;
#else
	return (team == TEAM_JINRAI) ? TEAM_NSF : TEAM_JINRAI;
#endif
}

int GetPickingTeam()
{
	if (_veto_stage == VETO_STAGE_FIRST_TEAM_BAN || _veto_stage == VETO_STAGE_FIRST_TEAM_PICK) {
		return _first_veto_team;
	}
	if (_veto_stage == VETO_STAGE_SECOND_TEAM_BAN || _veto_stage == VETO_STAGE_SECOND_TEAM_PICK) {
		return GetOpposingTeam(_first_veto_team);
	}
	return 0;
}

bool ResetPicksIfShould()
{
	if (Competitive_IsLive()) {
		PrintToChatAll("%s Game is already live, cancelling pending map picks.", g_sTag);
		PrintToConsoleAll("%s Game is already live, cancelling pending map picks.", g_sTag);
		LogToGame("%s Game is already live, cancelling pending map picks.", g_sTag);
		ClearVeto();
		return true;
	}
	if (IsPlayingTeamEmpty()) {
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
	for (int client = 1; client <= MaxClients; ++client) {
		if (!IsClientInGame(client)) {
			continue;
		}
		if (GetClientTeam(client) == team) {
			++num_players;
		}
	}
	return num_players;
}

stock int GetClientsExceptOne(int excluded_client, int[] out_clients, int max_clients)
{
	int num_clients = 0;
	for (int client = 1; client <= MaxClients; ++client) {
		if (num_clients >= max_clients) {
			break;
		}
		if (!IsClientInGame(client)) {
			continue;
		}
		if (client == excluded_client) {
			continue;
		}
		out_clients[num_clients++] = client;
	}
	return num_clients;
}

void PrintToTeam(int team, const String:message[], any ...)
{
	if (team < TEAM_NONE || team > TEAM_NSF) {
		ThrowError("Invalid team: %d", team);
	}
	
	decl String:formatMsg[512];
	VFormat(formatMsg, sizeof(formatMsg), message, 3);
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client)) {
			continue;
		}
		if (GetClientTeam(client) != team) {
			continue;
		}
		PrintToChat(client, formatMsg);
		PrintToConsole(client, formatMsg);
	}
}

void PrintToAllExceptTeam(int team, const String:message[], any ...)
{
	if (team < TEAM_NONE || team > TEAM_NSF) {
		ThrowError("Invalid team: %d", team);
	}
	
	decl String:formatMsg[512];
	VFormat(formatMsg, sizeof(formatMsg), message, 3);
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client)) {
			continue;
		}
		if (GetClientTeam(client) == team) {
			continue;
		}
		PrintToChat(client, formatMsg);
		PrintToConsole(client, formatMsg);
	}
}

void AnnounceMaps()
{
	if (ResetPicksIfShould()) {
		return;
	}
	
	if (_first_veto_team != TEAM_JINRAI && _first_veto_team != TEAM_NSF) {
		ThrowError("Invalid first team: %d", _first_veto_team);
	}
	
	int first_map, second_map, third_map;
	for (int i = 0; i < NUM_MAPS; ++i) {
		if (_is_picked_by[i] == GetOpposingTeam(_first_veto_team)) {
			first_map = i;
		}
		else if (_is_picked_by[i] == _first_veto_team) {
			second_map = i;
		}
		else if (_is_picked_by[i] == TEAM_SPECTATOR) {
			third_map = i;
		}
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
	Format(buffer, sizeof(buffer), "Map 1: %s", _maps[first_map]);
	panel.DrawText(buffer);
	PrintToConsoleAll("  - %s (%s pick)", buffer, (_first_veto_team == TEAM_JINRAI) ? jinrai_name : nsf_name);
	LogToGame("  - %s (%s pick)", buffer, (_first_veto_team == TEAM_JINRAI) ? jinrai_name : nsf_name);
	
	Format(buffer, sizeof(buffer), "Map 2: %s", _maps[second_map]);
	panel.DrawText(buffer);
	PrintToConsoleAll("  - %s (%s pick)", buffer, (_first_veto_team == TEAM_JINRAI) ? nsf_name: jinrai_name);
	LogToGame("  - %s (%s pick)", buffer, (_first_veto_team == TEAM_JINRAI) ? nsf_name: jinrai_name);
	
	Format(buffer, sizeof(buffer), "Map 3: %s", _maps[third_map]);
	panel.DrawText(buffer);
	PrintToConsoleAll("  - %s (random pick)\n", buffer);
	LogToGame("  - %s (random pick)\n", buffer);
	
	panel.DrawText(" ");
	panel.DrawItem("Exit");
	
	for (int client = 1; client <= MaxClients; ++client) {
		if (!IsClientInGame(client) || IsFakeClient(client)) {
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
	if (team != TEAM_JINRAI && team != TEAM_NSF) {
		ThrowError("Unexpected team index: %d", team);
	}
	
	GetConVarString((team == TEAM_JINRAI) ? g_hCvar_JinraiName : g_hCvar_NsfName, out_name, max_len);
	
	if (strlen(out_name) == 0) {
		strcopy(out_name, max_len, (team == TEAM_JINRAI) ? "Jinrai" : "NSF");
	}
}
