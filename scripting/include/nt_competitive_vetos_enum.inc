#if defined _NT_COMPETITIVE_VETOS_ENUM_INC_
    #endinput
#endif
#define _NT_COMPETITIVE_VETOS_ENUM_INC_

// "Team A" and "Team B" can be either Jinrai or NSF, and they may swap places
// after consecutive coin flips.

enum VetoStage_v2 {
    COINFLIP = 0,    // Flipping coin on who gets assigned as "Team A". Can be called multiple times.
    VETO_A,          // Team A vetoes a map.
    VETO_B,          // Team B vetoes a map.
    VETO_RANDOM,     // A map is randomly vetoed.
    PICK_A,          // Team A picks a map.
    PICK_B,          // Team B picks a map.
    PICK_RANDOM,     // A map is randomly picked.

    VETOSTAGE_ENUM_COUNT
};