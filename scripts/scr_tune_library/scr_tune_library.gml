// Script assets have changed for v2.3.0 see
// https://help.yoyogames.com/hc/en-us/articles/360005277377 for more information
#macro ev_midi 0

global.tune = [];

global.tune[1] = {
    events: [
        // 1
        { time: 0,    type: ev_midi, channel: 0, note: 64, velocity: 100 },   // e

        // 2
        //{ time: 500,  type: ev_structure, value: "bar" },

        // 3
        //{ time: 500,  type: ev_embellish, value: "{g}" },

        // 4
        { time: 500,  type: ev_midi, channel: 0, note: 57, velocity: 100 },   // A (high A)

        // 5
        //{ time: 1500, type: ev_embellish, value: "{GdGe}" },

        // 6
        { time: 1500, type: ev_midi, channel: 0, note: 57, velocity: 100 },   // A

        // 7
        { time: 2250, type: ev_midi, channel: 0, note: 59, velocity: 100 },   // B

        // 8
        //{ time: 2500, type: ev_embellish, value: "{gcd}" },

        // 9
        { time: 2500, type: ev_midi, channel: 0, note: 61, velocity: 100 },   // c

        // 10
        //{ time: 3000, type: ev_embellish, value: "{e}" },

        // 11
        { time: 3000, type: ev_midi, channel: 0, note: 57, velocity: 100 },   // A

        // 12
        //{ time: 3500, type: ev_embellish, value: "{gcd}" },

        // 13
        { time: 3500, type: ev_midi, channel: 0, note: 61, velocity: 100 },   // c

        // 14
        { time: 4000, type: ev_midi, channel: 0, note: 64, velocity: 100 },   // e

        // 15
        //{ time: 4500, type: ev_structure, value: "bar" },

        // 16
        //{ time: 4500, type: ev_embellish, value: "{ag}" },

        // 17
        { time: 4500, type: ev_midi, channel: 0, note: 69, velocity: 100 },   // a (high A)

        // 18
        //{ time: 5500, type: ev_embellish, value: "g" },

        // 19
        { time: 5500, type: ev_midi, channel: 0, note: 69, velocity: 100 },   // a

        // 20
        //{ time: 6500, type: ev_embellish, value: "{GdG}" },

        // 21
        { time: 6500, type: ev_midi, channel: 0, note: 69, velocity: 100 },   // a

        // 22
        { time: 7000, type: ev_midi, channel: 0, note: 64, velocity: 100 },   // e

        // 23
        //{ time: 7500, type: ev_embellish, value: "{gcd}" },

        // 24
        { time: 7500, type: ev_midi, channel: 0, note: 61, velocity: 100 },   // c

        // 25
        //{ time: 8000, type: ev_embellish, value: "e" },

        // 26
        { time: 8000, type: ev_midi, channel: 0, note: 57, velocity: 100 },   // a

        // 27
        //{ time: 8500, type: ev_structure, value: "bar" }
    ],

    metronome: {
        enabled: true,
        bpm: 60,
        beats_per_bar: 4,
        subdivision: "quarter",
        accent_pattern: [1],
        accent_note: 80,
        normal_note: 75,
        click_duration: 0.05,
        channel: 9,
        velocity: 100
    }
};

global.tune[2] =  {
    events: [
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
	],     
	metronome: {
        enabled: true,
        bpm: 120,
        beats_per_bar: 4,
        subdivision: "eighth",
        accent_pattern: [1],
        accent_note: 80,
        normal_note: 75,
        click_duration: 0.05,
		channel: 9,
		velocity: 100

    }
};

global.tune[3] = {
    events: [
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
    ],

    metronome: {
        enabled: true,
        bpm: 240,
        beats_per_bar: 4,
        subdivision: "eighth",
        accent_pattern: [1],
        accent_note: 80,
        normal_note: 75,
        click_duration: 0.05,
		channel: 9,
		velocity: 100

    }
};


global.tune[4] =  {
    events: [
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
],
metronome: {
        enabled: true,
        bpm: 120,
        beats_per_bar: 4,
        subdivision: "eighth",
        accent_pattern: [1],
        accent_note: 80,
        normal_note: 75,
        click_duration: 0.05,
		channel: 9,
		velocity: 100

    }
}
;

global.tune[5] =  {
    events: [
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
	],
	metronome: {
        enabled: true,
        bpm: 120,
        beats_per_bar: 4,
        subdivision: "eighth",
        accent_pattern: [1],
        accent_note: 80,
        normal_note: 75,
        click_duration: 0.05,
		channel: 9,
		velocity: 100

		}
	};
	



