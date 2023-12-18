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
    if (!ResetPicksIfShould())
    {
        DoVeto();
    }
    return Plugin_Stop;
}

public Action Timer_MapChangeInfoHelper(Handle timer)
{
    char[] msg = "[SM] If no admins are present, you can nominate & rtv in \
chat to change the maps according to the map picks.";

    PrintToChatAll("%s", msg);
    PrintToConsoleAll("%s", msg);
    return Plugin_Stop;
}
