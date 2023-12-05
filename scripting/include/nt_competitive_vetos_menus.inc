#if defined _NT_COMPETITIVE_VETOS_MENUS_INC_
    #endinput
#endif
#define _NT_COMPETITIVE_VETOS_MENUS_INC_

#include <nt_competitive_vetos_base>

#pragma semicolon 1
#pragma newdecls required

static Menu g_voteMenu = null;

public int MenuHandler_DoNothing(Menu menu, MenuAction action, int param1, int param2)
{
    return 0;
}

// Note that the callback params are guaranteed to actually represent client & selection
// only in some MenuActions. We are only subscribing to MenuAction_End and MenuAction_Select,
// so this is a safe assumption here.
public int MenuHandler_DoPick(Menu menu, MenuAction action, int client, int selection)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }
    else if (action == MenuAction_Cancel)
    {
        return 0;
    }
    else if (action != MenuAction_Select)
    {
        ThrowError("Unexpected MenuAction %d", action);
    }
    // MenuAction_Select

    bool veto_was_cancelled = ResetPicksIfShould();

    if (!veto_was_cancelled && client > 0 && client <= MaxClients &&
        IsClientInGame(client) && !IsFakeClient(client))
    {
        int client_team = GetClientTeam(client);
        if (client_team == GetPickingTeam())
        {
            char jinrai_name[MAX_CUSTOM_TEAM_NAME_LEN];
            char nsf_name[MAX_CUSTOM_TEAM_NAME_LEN];
            GetCompetitiveTeamName(TEAM_JINRAI, jinrai_name, sizeof(jinrai_name));
            GetCompetitiveTeamName(TEAM_NSF, nsf_name, sizeof(nsf_name));

            char chosen_map[PLATFORM_MAX_PATH];
            if (!menu.GetItem(selection, chosen_map, sizeof(chosen_map)))
            {
                ThrowError("GetItem failed");
            }
            else if (StrEqual(chosen_map, ITEM_DISABLED_STR))
            {
                ThrowError("Client chose a disabled str from menu (%d)", selection);
            }

            ConfirmSoloMapPick(client, client_team, chosen_map);
        }
    }
    menu.Cancel();
    return 0;
}

void ConfirmSoloMapPick(int client, int team, const char[] map_name)
{
    if (team != TEAM_JINRAI && team != TEAM_NSF)
    {
        ThrowError("Unexpected team: %d", team);
    }
    else if (strlen(map_name) == 0)
    {
        ThrowError("Empty map name");
    }

    strcopy(_pending_map_pick_nomination_for_vote,
        sizeof(_pending_map_pick_nomination_for_vote), map_name);

    Menu vote_menu = new Menu(MenuHandler_ConfirmSoloMapPick, MenuAction_End);
    if (!vote_menu)
    {
        ThrowError("Failed to create Menu");
    }

    vote_menu.ExitButton = false;
    vote_menu.VoteResultCallback = VoteHandler_ConfirmSoloMapPick;

    VetoStage stage = GetCurrentVetoStage();

    bool is_ban_stage = (stage == VETO_A || stage == VETO_B);

    vote_menu.SetTitle("Team %s suggestion by %N: %s (need at least 50%c consensus)",
        is_ban_stage ? "VETO" : "PICK",
        client,
        map_name,
        '%'); // Note: the panel formats text differently, so need to use %c -> '%' for percentages here.

    vote_menu.AddItem("yes", "Vote yes", ITEMDRAW_DEFAULT);
    vote_menu.AddItem("no", "Vote no", ITEMDRAW_DEFAULT);

    int voters[NEO_MAX_PLAYERS];
    int num_voters;
    for (int iter_client = 1; iter_client <= MaxClients; ++iter_client)
    {
        if (!IsClientInGame(iter_client) || IsFakeClient(iter_client))
        {
            continue;
        }
        if (GetClientTeam(iter_client) != team)
        {
            continue;
        }
        voters[num_voters++] = iter_client;
    }

    if (IsVoteInProgress())
    {
        CancelVote();
        PrintToChatAll("%s Cancelling existing vote because veto voting is currently active.", g_sTag);
    }
    vote_menu.DisplayVote(voters, num_voters, MENU_TIME_FOREVER);
    if (g_voteMenu != null)
    {
        delete g_voteMenu;
    }
    g_voteMenu = vote_menu;
}

public int MenuHandler_ConfirmSoloMapPick(Menu menu, MenuAction action,
    int param1, int param2)
{
    if (action == MenuAction_End)
    {
        if (g_voteMenu == menu && menu != null)
        {
            delete g_voteMenu;
        }
    }
    return 0;
}

public void VoteHandler_ConfirmSoloMapPick(Menu menu, int num_votes, int num_clients,
    const int[][] client_info, int num_items, const int[][] item_info)
{
    // Vote has been reset by this plugin (admin reset, etc.)
    if (!IsVetoActive())
    {
        return;
    }

    // Nobody voted yes/no, don't do anything yet.
    if (num_votes == 0)
    {
        strcopy(_pending_map_pick_nomination_for_vote,
            sizeof(_pending_map_pick_nomination_for_vote), "");
        return;
    }

    int num_yes_votes;
    int num_no_votes;
    int voting_team;

    for (int i = 0; i < num_clients; ++i)
    {
        if (voting_team == 0)
        {
            voting_team = GetClientTeam(client_info[i][0]);
            if (voting_team != TEAM_JINRAI && voting_team != TEAM_NSF)
            {
                ThrowError("Failed to get a valid voting team (%d)", voting_team);
            }
        }

        if (client_info[i][1] == 0)
        {
            ++num_yes_votes;
        }
        else
        {
            ++num_no_votes;
        }
    }

    if (num_yes_votes >= num_no_votes)
    {
        VetoStage stage = GetCurrentVetoStage();

        char jinrai_name[MAX_CUSTOM_TEAM_NAME_LEN];
        char nsf_name[MAX_CUSTOM_TEAM_NAME_LEN];
        GetCompetitiveTeamName(TEAM_JINRAI, jinrai_name, sizeof(jinrai_name));
        GetCompetitiveTeamName(TEAM_NSF, nsf_name, sizeof(nsf_name));

        if (stage == VETO_A || stage == VETO_B)
        {
            SetMapVetoPick(voting_team, _pending_map_pick_nomination_for_vote);
            EmitSoundToAll(g_sSound_Veto);

            PrintToAllExceptTeam(voting_team, "[VETO] Team %s vetoes map: %s",
                (voting_team == TEAM_JINRAI) ? jinrai_name : nsf_name,
                _pending_map_pick_nomination_for_vote);
            LogToGame("[VETO] Team %s vetoes map: %s",
                (voting_team == TEAM_JINRAI) ? jinrai_name : nsf_name,
                _pending_map_pick_nomination_for_vote);
        }
        else if (stage == PICK_A || stage == PICK_B)
        {
            SetMapVetoPick(voting_team, _pending_map_pick_nomination_for_vote);
            EmitSoundToAll(g_sSound_Pick);

            PrintToAllExceptTeam(voting_team, "[PICK] Team %s picks map: %s",
                (voting_team == TEAM_JINRAI) ? jinrai_name : nsf_name,
                _pending_map_pick_nomination_for_vote);
            LogToGame("[PICK] Team %s picks map: %s",
                (voting_team == TEAM_JINRAI) ? jinrai_name : nsf_name,
                _pending_map_pick_nomination_for_vote);
        }
        else
        {
            ThrowError("Unexpected veto stage: %d", stage);
        }

        PrintToTeam(voting_team,
            "%s Your team %sed map %s (%d%s \"yes\" votes of %d votes total).",
            (stage == VETO_A || stage == VETO_B) ? "[VETO]" : "[PICK]",
            (stage == VETO_A || stage == VETO_B) ? "veto" : "pick",
            _pending_map_pick_nomination_for_vote,
            (num_yes_votes == 0) ? 100 : ((1 - (num_no_votes / num_yes_votes)) * 100),
            "％", // HACK: this is the Unicode full-width percentage symbol; I've no idea why the regular "%" sign formatting doesn't work here.
                  // The "%" displays correctly for client console but disappears in chat, and "%%" displays correctly for chat but doubly in console.
                  // Since using the word "percentage" here stretches the chat line over the line break boundary & makes the output look messy,
                  // I'm just using the Unicode here since it should be supported by nearly all systems.
            num_votes);
    }
    else
    {
        PrintToTeam(voting_team, "%s Need at least 50%s of \"yes\" votes (got %d%s).",
            g_sTag,
            "%",
            (num_no_votes == 0) ? 0 : (num_yes_votes / num_no_votes),
            "%");
    }

    strcopy(_pending_map_pick_nomination_for_vote,
        sizeof(_pending_map_pick_nomination_for_vote), "");

    if (IsVetoActive())
    {
        DoVeto();
    }
}
