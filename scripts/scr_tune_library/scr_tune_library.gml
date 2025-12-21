// Script assets have changed for v2.3.0 see
// https://help.yoyogames.com/hc/en-us/articles/360005277377 for more information
#macro ev_midi 0

global.tune = [];

global.tune[1] = [
    { time: 250, type: ev_midi, channel: 0, note: 60, velocity: 100 },
    { time: 300, type: ev_midi, channel: 0, note: 60, velocity: 100 },
	{ time: 500, type: ev_midi, channel: 0, note: 64, velocity: 100 },
    { time: 750, type: ev_midi, channel: 0, note: 64, velocity: 100 },
	{ time: 1000, type: ev_midi, channel: 0, note: 67, velocity: 100 },
    { time: 1500, type: ev_midi, channel: 0, note: 67, velocity: 100 },
	{ time: 2500, type: ev_midi, channel: 0, note: 64, velocity: 100 },
    { time: 3500, type: ev_midi, channel: 0, note: 64, velocity: 100 },
	{ time: 4500, type: ev_midi, channel: 0, note: 60, velocity: 100 },
    { time: 5500, type: ev_midi, channel: 0, note: 60, velocity: 100 }	
];

global.tune[2] = [
    { time: 250, type: ev_midi, channel: 0, note: 55, velocity: 90 },
    { time: 250, type: ev_midi, channel: 0, note: 57, velocity: 90 },
	{ time: 500, type: ev_midi, channel: 0, note: 59, velocity: 90 },	
	{ time: 250, type: ev_midi, channel: 0, note: 60, velocity: 90 },
	{ time: 250, type: ev_midi, channel: 0, note: 57, velocity: 90 },
	{ time: 500, type: ev_midi, channel: 0, note: 55, velocity: 20 },	
	{ time: 250, type: ev_midi, channel: 0, note: 55, velocity: 90 },
    { time: 250, type: ev_midi, channel: 0, note: 57, velocity: 90 },
	{ time: 500, type: ev_midi, channel: 0, note: 59, velocity: 90 },	
	{ time: 250, type: ev_midi, channel: 0, note: 60, velocity: 90 },
	{ time: 250, type: ev_midi, channel: 0, note: 57, velocity: 90 },
	{ time: 250, type: ev_midi, channel: 0, note: 55, velocity: 20 },
	{ time: 125, type: ev_midi, channel: 0, note: 59, velocity: 90 }
];

global.tune[3] = [
    { time: 250, type: ev_midi, channel: 0, note: 60, velocity: 100 },
    { time: 500, type: ev_midi, channel: 0, note: 60, velocity: 100 },
	{ time: 750, type: ev_midi, channel: 0, note: 64, velocity: 100 },
    { time: 1000, type: ev_midi, channel: 0, note: 64, velocity: 100 },
	{ time: 1250, type: ev_midi, channel: 0, note: 67, velocity: 100 },
    { time: 1500, type: ev_midi, channel: 0, note: 67, velocity: 100 },
	{ time: 1750, type: ev_midi, channel: 0, note: 64, velocity: 100 },
    { time: 2000, type: ev_midi, channel: 0, note: 64, velocity: 100 },
	{ time: 2250, type: ev_midi, channel: 0, note: 60, velocity: 100 },
    { time: 2500, type: ev_midi, channel: 0, note: 60, velocity: 100 }	
];

global.tune[4] = [
    // ---- BAR 1 ----
    { time: 0,    type: ev_midi, channel: 9, note: 42, velocity: 100 }, // HH beat 1
    { time: 0,    type: ev_midi, channel: 9, note: 36, velocity: 110 }, // Kick

    { time: 500,  type: ev_midi, channel: 9, note: 42, velocity: 100 }, // HH beat 2
    { time: 500,  type: ev_midi, channel: 9, note: 38, velocity: 110 }, // Snare

    { time: 1000, type: ev_midi, channel: 9, note: 42, velocity: 100 }, // HH beat 3
    { time: 1000, type: ev_midi, channel: 9, note: 36, velocity: 110 }, // Kick

    { time: 1500, type: ev_midi, channel: 9, note: 42, velocity: 100 }, // HH beat 4
    { time: 1500, type: ev_midi, channel: 9, note: 38, velocity: 110 }, // Snare

    // ---- BAR 2 ----
    { time: 2000, type: ev_midi, channel: 9, note: 42, velocity: 100 },
    { time: 2000, type: ev_midi, channel: 9, note: 36, velocity: 110 },

    { time: 2500, type: ev_midi, channel: 9, note: 42, velocity: 100 },
    { time: 2500, type: ev_midi, channel: 9, note: 38, velocity: 110 },

    { time: 3000, type: ev_midi, channel: 9, note: 42, velocity: 100 },
    { time: 3000, type: ev_midi, channel: 9, note: 36, velocity: 110 },

    { time: 3500, type: ev_midi, channel: 9, note: 42, velocity: 100 },
    { time: 3500, type: ev_midi, channel: 9, note: 38, velocity: 110 },

    // ---- BAR 3 ----
    { time: 4000, type: ev_midi, channel: 9, note: 42, velocity: 100 },
    { time: 4000, type: ev_midi, channel: 9, note: 36, velocity: 110 },

    { time: 4500, type: ev_midi, channel: 9, note: 42, velocity: 100 },
    { time: 4500, type: ev_midi, channel: 9, note: 38, velocity: 110 },

    { time: 5000, type: ev_midi, channel: 9, note: 42, velocity: 100 },
    { time: 5000, type: ev_midi, channel: 9, note: 36, velocity: 110 },

    { time: 5500, type: ev_midi, channel: 9, note: 42, velocity: 100 },
    { time: 5500, type: ev_midi, channel: 9, note: 38, velocity: 110 },

    // ---- BAR 4 ----
    { time: 6000, type: ev_midi, channel: 9, note: 42, velocity: 100 },
    { time: 6000, type: ev_midi, channel: 9, note: 36, velocity: 110 },

    { time: 6500, type: ev_midi, channel: 9, note: 42, velocity: 100 },
    { time: 6500, type: ev_midi, channel: 9, note: 38, velocity: 110 },

    { time: 7000, type: ev_midi, channel: 9, note: 42, velocity: 100 },
    { time: 7000, type: ev_midi, channel: 9, note: 36, velocity: 110 },

    { time: 7500, type: ev_midi, channel: 9, note: 42, velocity: 100 },
    { time: 7500, type: ev_midi, channel: 9, note: 38, velocity: 110 }
];

global.tune[5] = [
    // ---- BAR 1 ----
    // Hi-hats every 250ms
    { time: 0,    type: ev_midi, channel: 9, note: 42, velocity: 90 },	    
	{ time: 0,    type: ev_midi, channel: 9, note: 36, velocity: 100 }, // Kick 1
	{ time: 250,  type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 500,  type: ev_midi, channel: 9, note: 38, velocity: 110 }, // Snare 2
    { time: 500,  type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 750,  type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 1000, type: ev_midi, channel: 9, note: 36, velocity: 125 }, // STRONG Kick 3
    { time: 1000, type: ev_midi, channel: 9, note: 42, velocity: 110 }, // HH accent on 3
    { time: 1250, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 1500, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 1500, type: ev_midi, channel: 9, note: 38, velocity: 110 }, // Snare 4	
    { time: 1750, type: ev_midi, channel: 9, note: 42, velocity: 90 },

   
    // ---- BAR 2 ----
    { time: 2000, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 2000, type: ev_midi, channel: 9, note: 36, velocity: 100 },
    { time: 2250, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 2500, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 2500, type: ev_midi, channel: 9, note: 38, velocity: 110 },
    { time: 2750, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 3000, type: ev_midi, channel: 9, note: 42, velocity: 110 },
    { time: 3000, type: ev_midi, channel: 9, note: 36, velocity: 125 },
    { time: 3250, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 3500, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 3500, type: ev_midi, channel: 9, note: 38, velocity: 110 },
    { time: 3750, type: ev_midi, channel: 9, note: 42, velocity: 90 },


    // ---- BAR 3 ----
    { time: 4000, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 4000, type: ev_midi, channel: 9, note: 36, velocity: 100 },
    { time: 4250, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 4500, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 4500, type: ev_midi, channel: 9, note: 38, velocity: 110 },
    { time: 4750, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 5000, type: ev_midi, channel: 9, note: 42, velocity: 110 },
    { time: 5000, type: ev_midi, channel: 9, note: 36, velocity: 125 },
    { time: 5250, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 5500, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 5500, type: ev_midi, channel: 9, note: 38, velocity: 110 },
    { time: 5750, type: ev_midi, channel: 9, note: 42, velocity: 90 },


    // ---- BAR 4 ----
    { time: 6000, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 6250, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 6500, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 6750, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 7000, type: ev_midi, channel: 9, note: 42, velocity: 110 },
    { time: 7250, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 7500, type: ev_midi, channel: 9, note: 42, velocity: 90 },
    { time: 7750, type: ev_midi, channel: 9, note: 42, velocity: 90 },

//    { time: 6000, type: ev_midi, channel: 9, note: 36, velocity: 100 },
//    { time: 6500, type: ev_midi, channel: 9, note: 38, velocity: 110 },
//    { time: 7000, type: ev_midi, channel: 9, note: 36, velocity: 125 },
//    { time: 7500, type: ev_midi, channel: 9, note: 38, velocity: 110 }
];