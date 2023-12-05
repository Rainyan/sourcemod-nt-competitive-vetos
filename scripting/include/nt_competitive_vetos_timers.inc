#if defined _NT_COMPETITIVE_VETOS_TIMERS_INC_
    #endinput
#endif
#define _NT_COMPETITIVE_VETOS_TIMERS_INC_

#pragma semicolon 1
#pragma newdecls required

public Action Timer_CoinFlip(Handle timer)
{
    if (IsVetoActive() && !ResetPicksIfShould())
    {
        CoinFlip();
    }
    return Plugin_Stop;
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

public Action Timer_MapChangeInfoHelper(Handle timer)
{
    char[] msg = "[SM] If no admins are present, you can nominate & rtv in chat to change \
the maps according to the map picks.";

    PrintToChatAll("%s", msg);
    PrintToConsoleAll("%s", msg);
    return Plugin_Stop;
}

#if defined(DEBUG_FAKE_VETOS)
public Action Timer_FakeCoinFlip(Handle timer)
{
    _first_veto_team = GetRandomPlayerTeam();

    Call_StartForward(g_hForwardVetoStageUpdate);
    Call_PushCell(VETO_STAGE_COIN_FLIP_RESULT);
    Call_PushCell(_first_veto_team);
    Call_Finish();

    CreateTimer(DEBUG_FAKE_VETOS_TIMER, Timer_FakeFirstVeto);
    return Plugin_Stop;
}

public Action Timer_FakeFirstVeto(Handle timer)
{
    int map = GetURandomInt() % NUM_RANDOM_MAPS;
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

public Action Cmd_AdminDebug_FakeVeto(int client, int argc)
{
    Call_StartForward(g_hForwardVetoStageUpdate);
    Call_PushCell(VETO_STAGE_COIN_FLIP);
    Call_PushCell(-1);
    Call_Finish();

    CreateTimer(DEBUG_FAKE_VETOS_TIMER, Timer_FakeCoinFlip);
    return Plugin_Handled;
}

public Action Timer_FakeSecondVeto(Handle timer)
{
    int map;
    do
    {
        map = GetURandomInt() % NUM_RANDOM_MAPS;
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
        map = GetURandomInt() % NUM_RANDOM_MAPS;
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
        map = GetURandomInt() % NUM_RANDOM_MAPS;
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
        map = GetURandomInt() % NUM_RANDOM_MAPS;
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