tune_data = {
    title: "Peter MacKenzies Warren",
    bpm: 72,
    beats_per_measure: 4,
    beat_note: 4,
    parts: [
        {
            instrument: "chanter",
            events: [
				{ time:0, delta:0, event:144, channel:1, note:NOTE_G, velocity:90 },
				{ time:250, delta:250, event:128, channel:1, note:NOTE_G, velocity:0 },
				{ time:250, delta:0, event:144, channel:1, note:NOTE_A, velocity:90 },
				{ time:500, delta:250, event:128, channel:1, note:NOTE_A, velocity:0 },
				{ time:500, delta:0, event:144, channel:1, note:NOTE_B, velocity:90 },
				{ time:750, delta:0, event:128, channel:1, note:NOTE_B, velocity:0 },
				{ time:750, delta:250, event:144, channel:1, note:NOTE_c, velocity:70},
				{ time:1000, delta:0, event:128, channel:1, note:NOTE_c, velocity:0 },
				{ time:1000, delta:250, event:144, channel:1, note:NOTE_d, velocity:70 },
				{ time:1250, delta:250, event:144, channel:1, note:NOTE_d, velocity:70, length:70 }
            ]
        },
        {
            instrument: "drums",
            events: [
                { time:0,   event:144, note:38, velocity:100 }, // snare hit
                { time:500, event:128, note:38, velocity:0 }
            ]
        }
    ]
};