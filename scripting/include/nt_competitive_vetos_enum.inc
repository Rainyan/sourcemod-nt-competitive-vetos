#if defined _NT_COMPETITIVE_VETOS_ENUM_INC_
    #endinput
#endif

#define _NT_COMPETITIVE_VETOS_ENUM_INC_

// Please note that "Team 1" and "Team 2" in the specific veto stage comments
// below do not refer to any actual team indices; "Team 1" can be either TEAM_JINRAI
// or TEAM_NSF, and "Team 2" will be whichever of the two "Team 1" isn't.
// As such, the veto/pick order can be either one of:
//   - Jinrai, NSF, NSF, Jinrai, random
//   - NSF, Jinrai, Jinrai, NSF, random
enum VetoStage {
    VETO_STAGE_INACTIVE = 0,         // - Vetoing is not happening at all currently (or was finished)

    VETO_STAGE_COIN_FLIP,            // - Doing a coin flip to decide who vetoes first

    VETO_STAGE_FIRST_TEAM_BAN,       // - Currently deciding on the first veto (Team 1)

    VETO_STAGE_SECOND_TEAM_BAN,      // - Currently deciding on the second veto (Team 2)

    VETO_STAGE_SECOND_TEAM_PICK,     // - Currently deciding on the first pick (Team 2)

    VETO_STAGE_FIRST_TEAM_PICK,      // - Currently deciding on the second pick (Team 1)

    VETO_STAGE_RANDOM_THIRD_MAP,     // - Currently deciding on the third random map.
                                     //   VETO_STAGE_RANDOM_THIRD_MAP will be followed
                                     //   by VETO_STAGE_INACTIVE upon veto completion.

    NUM_STAGES                       // - Unused
};
