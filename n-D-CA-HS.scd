(
var dimensions = 2, gridSize = 8, currentRule = \conway;
var baseFreq = 100, generationTime = 1.0, generation = 0;
var arpeggiate = false, arpPattern = \up;
var harmonicRatios, grid, running = false;
var activeVoices, arpeggiator, updateTask;
var window, statusText;
var rules, isTransitioning = false;
var initDensity = 0.4;

var currentBirth, currentSurvival;
var ruleEditorView, birthButtons = [], survivalButtons = [];
var leftColumn;

var init = {
    rules = Dictionary[
        \conway -> (name: "GoL", birth: [3], survival: [2, 3]),
        \fredkin -> (name: "Fredkin", birth: [1, 3, 5, 7], survival: [1, 3, 5, 7]),
        \brain -> (name: "Brian's Brain", birth: [2], survival: [], special: true, states: 3),
        \seeds -> (name: "Seeds", birth: [2], survival: []),
        \daynight -> (name: "Day & Night", birth: [3, 6, 7, 8], survival: [3, 4, 6, 7, 8])
    ];

    currentBirth = rules[currentRule][\birth].copy;
    currentSurvival = rules[currentRule][\survival].copy;

    harmonicRatios = Dictionary[
        \x -> [8, 7],
        \y -> [7, 6],
        \z -> [6, 5]
    ];

    activeVoices = Dictionary.new;
    initializeGrid.();
    createSynthDefs.();

    "CA HS initialized with GoL".postln;
};

var getCurrentRule = {
    var baseRule = rules[currentRule];
    var liveRule = baseRule.copy;

    liveRule[\birth] = currentBirth;
    liveRule[\survival] = currentSurvival;

    liveRule;
};

var loadRuleIntoEditor = {
    var rule = rules[currentRule];
    currentBirth = rule[\birth].copy;
    currentSurvival = rule[\survival].copy;

    updateRuleButtons.();

    ("Loaded rule: % - Birth: % Survival: %").format(
        rule[\name], currentBirth, currentSurvival
    ).postln;
};

var createSynthDefs = {
    SynthDef(\caHarmonic, {
        |freq = 440, amp = 0.3, gate = 1, attack = 0.05, decay = 0.1,
         sustain = 0.7, release = 0.3, filterFreq = 2000, filterQ = 1,
         pan = 0|

        var env, sig, filter;

        env = EnvGen.kr(
            Env.adsr(attack, decay, sustain, release),
            gate, doneAction: Done.freeSelf
        );

        sig = Mix([
            SinOsc.ar(freq, 0, 0.4),
            SinOsc.ar(freq * 2, 0, 0.2),
            SinOsc.ar(freq * 3, 0, 0.1),
            Pulse.ar(freq, 0.3, 0.15)
        ]);

        filter = RLPF.ar(sig, filterFreq * (1 + (env * 0.5)), 1/filterQ);
        sig = filter * env * amp;
        sig = Pan2.ar(sig, pan);
        sig = Compander.ar(sig, sig, 0.5, 1, 0.1, 0.01, 0.1);

        Out.ar(0, sig);
    }).add;

    SynthDef(\caArp, {
        |freq = 440, amp = 0.2, dur = 0.1, attack = 0.01, release = 0.05,
         filterFreq = 3000, pan = 0, cellX = 0, cellY = 0, cellZ = 0|

        var env, sig, filter, modFreq, ampMod, chorus;
        var sustain = dur - attack - release;
        var harmSig, noiseSig, subSig, crystalSig;

        env = EnvGen.kr(
            Env([0, 1, 0.98, 0], [attack, sustain * 0.5, sustain * 0.5 + release], [1, 0, 0]),
            doneAction: Done.freeSelf
        );

        modFreq = freq * 0.08 + (cellX * 1.5) + (cellY * 1.2);
        ampMod = LFNoise1.kr(freq * 0.01 + cellZ, 0.15) + 1;

        harmSig = Mix([
            SinOsc.ar(freq, 0, 0.35),
            SinOsc.ar(freq * 2, 0, 0.2),
            SinOsc.ar(freq * 3, 0, 0.12),
            SinOsc.ar(freq * 1.5, 0, 0.08),
            Saw.ar(freq, 0.06),
        ]);

        subSig = Mix([
            SinOsc.ar(freq / 2, 0, 0.15),
            SinOsc.ar(freq / 3, 0, 0.08),
        ]) * LFNoise1.kr(cellY + 2, 0.3, 0.7);

        crystalSig = Mix([
            SinOsc.ar(freq * 4, 0, 0.06),
            SinOsc.ar(freq * 5, 0, 0.04),
            SinOsc.ar(freq * 7, 0, 0.03),
        ]) * env.squared;

        noiseSig = Mix([
            PinkNoise.ar(0.01) * BPF.ar(WhiteNoise.ar, freq * 2, 0.1),
            Dust.ar(20 + (cellZ * 10), 0.015) * SinOsc.ar(freq)
        ]) * env;

        sig = harmSig + subSig + crystalSig + noiseSig;

        chorus = Mix([
            DelayC.ar(sig, 0.02, 0.007 + LFNoise1.kr(0.5, 0.001), 0.3),
            DelayC.ar(sig, 0.02, 0.012 + LFNoise1.kr(0.7, 0.001), 0.2),
            DelayC.ar(sig, 0.02, 0.018 + LFNoise1.kr(0.3, 0.001), 0.1)
        ]);

        sig = sig * 0.8 + (chorus * 0.2);

        filter = RLPF.ar(
            sig,
            filterFreq * (0.8 + (env * 1.2) + (cellZ * 0.3)),
            0.1 + (cellY * 0.15 / gridSize)
        );

        filter = filter + (RHPF.ar(sig, freq * 4, 0.3) * env.squared * 0.1);

        sig = filter * env * amp * ampMod;

        sig = (sig * 0.9) + (tanh(sig * 1.2) * 0.1);

        sig = Pan2.ar(sig, pan + LFNoise1.kr(0.2, 0.05));

        sig = sig + Mix([
            AllpassC.ar(sig, 0.2, 0.038 + (cellX * 0.002), 2.0) * 0.06,
            AllpassC.ar(sig, 0.2, 0.062 + (cellY * 0.002), 1.5) * 0.04,
            AllpassC.ar(sig, 0.2, 0.101 + (cellZ * 0.001), 1.0) * 0.03
        ]);

        Out.ar(0, sig);
    }).add;
};

var initializeGrid = {
    var rule;
    var deadProb, aliveProb, dyingProb;

    rule = getCurrentRule.();

    if ((rule[\special] == true) && ((rule[\states] ? 2) > 2)) {
        deadProb = 1.0 - initDensity;
        aliveProb = initDensity * 0.7;
        dyingProb = initDensity * 0.3;
    } {
        deadProb = 1.0 - initDensity;
        aliveProb = initDensity;
    };

    if (dimensions == 1) {
        grid = Array.fill(gridSize, {
            if ((rule[\special] == true) && ((rule[\states] ? 2) > 2)) {
                [0, 1, 2].wchoose([deadProb, aliveProb, dyingProb])
            } {
                [0, 1].wchoose([deadProb, aliveProb])
            }
        });
    } {
        if (dimensions == 2) {
            grid = Array.fill(gridSize, {
                Array.fill(gridSize, {
                    if ((rule[\special] == true) && ((rule[\states] ? 2) > 2)) {
                        [0, 1, 2].wchoose([deadProb, aliveProb, dyingProb])
                    } {
                        [0, 1].wchoose([deadProb, aliveProb])
                    }
                })
            });
        } {
            if (dimensions == 3) {
                grid = Array.fill(gridSize, {
                    Array.fill(gridSize, {
                        Array.fill(gridSize, {
                            if ((rule[\special] == true) && ((rule[\states] ? 2) > 2)) {
                                [0, 1, 2].wchoose([deadProb, aliveProb, dyingProb])
                            } {
                                [0, 1].wchoose([deadProb, aliveProb])
                            }
                        })
                    })
                });
            }
        }
    };

    generation = 0;

    {
        var activeCells = getActiveCells.();
        "Grid initialized with % active cells (%.1f% density)".format(activeCells.size, (activeCells.size / (gridSize ** dimensions) * 100)).postln;
    }.defer(0.1);
};

var countNeighbors = { |x, y = 0, z = 0|
    var neighbors = 0;
    var rule = getCurrentRule.();
    var isMultiState = (rule[\special] == true) && (currentRule == \brain);

    if ((rule[\useVonNeumann] == true)) {
        if (dimensions == 1) {
            var prev = (x - 1 + gridSize) % gridSize;
            var next = (x + 1) % gridSize;
            if (isMultiState) {
                if (grid[prev] == 1) { neighbors = neighbors + 1 };
                if (grid[next] == 1) { neighbors = neighbors + 1 };
            } {
                if (grid[prev] > 0) { neighbors = neighbors + 1 };
                if (grid[next] > 0) { neighbors = neighbors + 1 };
            };
        } {
            if (dimensions == 2) {
                [[-1, 0], [1, 0], [0, -1], [0, 1]].do { |delta|
                    var nx = (x + delta[0] + gridSize) % gridSize;
                    var ny = (y + delta[1] + gridSize) % gridSize;
                    if (isMultiState) {
                        if (grid[nx][ny] == 1) { neighbors = neighbors + 1 };
                    } {
                        if (grid[nx][ny] > 0) { neighbors = neighbors + 1 };
                    };
                };
            } {
                if (dimensions == 3) {
                    [[-1, 0, 0], [1, 0, 0], [0, -1, 0], [0, 1, 0], [0, 0, -1], [0, 0, 1]].do { |delta|
                        var nx = (x + delta[0] + gridSize) % gridSize;
                        var ny = (y + delta[1] + gridSize) % gridSize;
                        var nz = (z + delta[2] + gridSize) % gridSize;
                        if (isMultiState) {
                            if (grid[nx][ny][nz] == 1) { neighbors = neighbors + 1 };
                        } {
                            if (grid[nx][ny][nz] > 0) { neighbors = neighbors + 1 };
                        };
                    };
                }
            }
        };
    } {
        if (dimensions == 1) {
            var prev = (x - 1 + gridSize) % gridSize;
            var next = (x + 1) % gridSize;
            if (isMultiState) {
                if (grid[prev] == 1) { neighbors = neighbors + 1 };
                if (grid[next] == 1) { neighbors = neighbors + 1 };
            } {
                if (grid[prev] > 0) { neighbors = neighbors + 1 };
                if (grid[next] > 0) { neighbors = neighbors + 1 };
            };
        } {
            if (dimensions == 2) {
                (-1..1).do { |i|
                    (-1..1).do { |j|
                        if ((i != 0) || (j != 0)) {
                            var nx = (x + i + gridSize) % gridSize;
                            var ny = (y + j + gridSize) % gridSize;
                            if (isMultiState) {
                                if (grid[nx][ny] == 1) { neighbors = neighbors + 1 };
                            } {
                                if (grid[nx][ny] > 0) { neighbors = neighbors + 1 };
                            };
                        };
                    };
                };
            } {
                if (dimensions == 3) {
                    (-1..1).do { |i|
                        (-1..1).do { |j|
                            (-1..1).do { |k|
                                if ((i != 0) || (j != 0) || (k != 0)) {
                                    var nx = (x + i + gridSize) % gridSize;
                                    var ny = (y + j + gridSize) % gridSize;
                                    var nz = (z + k + gridSize) % gridSize;
                                    if (isMultiState) {
                                        if (grid[nx][ny][nz] == 1) { neighbors = neighbors + 1 };
                                    } {
                                        if (grid[nx][ny][nz] > 0) { neighbors = neighbors + 1 };
                                    };
                                };
                            };
                        };
                    };
                }
            }
        };
    };

    neighbors;
};

var applyRule = { |cellState, neighbors|
    var rule = getCurrentRule.();
    var newState = 0;

    if ((rule[\special] == true) && (currentRule == \brain)) {
        if (cellState == 2) {
            newState = 0;
        } {
            if (cellState == 1) {
                newState = 2;
            } {
                if ((rule[\birth] ? []).includes(neighbors)) {
                    newState = 1;
                } {
                    newState = 0;
                };
            };
        };
    } {
        if (cellState > 0) {
            if ((rule[\survival] ? []).includes(neighbors)) {
                newState = 1;
            } {
                newState = 0;
            };
        } {
            if ((rule[\birth] ? []).includes(neighbors)) {
                newState = 1;
            } {
                newState = 0;
            };
        };
    };

    newState;
};

var toggleNeighbor = { |neighborCount, isBirth = true|
    var array = if (isBirth) { currentBirth } { currentSurvival };
    var index = array.indexOf(neighborCount);

    if (index.isNil) {
        array = array ++ [neighborCount];
        array.sort;
    } {
        array.removeAt(index);
    };

    if (isBirth) {
        currentBirth = array;
    } {
        currentSurvival = array;
    };

    updateRuleButtons.();

    initializeGrid.();
    updateStatus.();

    ("Live edit - Birth: % Survival: %").format(currentBirth, currentSurvival).postln;
};

var updateRuleButtons = {
    if (birthButtons.notNil && survivalButtons.notNil) {
        16.do { |i|
            if (birthButtons[i].notNil) {
                birthButtons[i].value = if (currentBirth.includes(i)) { 1 } { 0 };
            };
            if (survivalButtons[i].notNil) {
                survivalButtons[i].value = if (currentSurvival.includes(i)) { 1 } { 0 };
            };
        };
    };
};

var createRuleEditor = { |parent|

    ruleEditorView = CompositeView(parent, (parent.bounds.width-10)@200);
    ruleEditorView.decorator = FlowLayout(ruleEditorView.bounds, 5@5, 2@2);

    StaticText(ruleEditorView, 100@20).string_("Birth (B):");
    ruleEditorView.decorator.nextLine;

    birthButtons = Array.newClear(16);
    16.do { |i|
        birthButtons[i] = Button(ruleEditorView, 30@25)
            .states_([[i.asString, Color.black, Color.white], [i.asString, Color.white, Color.blue]])
            .value_(if (currentBirth.includes(i)) { 1 } { 0 })
            .action_({ |btn|
                toggleNeighbor.(i, true);
            });

        if ((i % 8) == 7) { ruleEditorView.decorator.nextLine };
    };

    ruleEditorView.decorator.nextLine;
    ruleEditorView.decorator.nextLine;

    StaticText(ruleEditorView, 100@20).string_("Survival (S):");
    ruleEditorView.decorator.nextLine;

    survivalButtons = Array.newClear(16);
    16.do { |i|
        survivalButtons[i] = Button(ruleEditorView, 30@25)
            .states_([[i.asString, Color.black, Color.white], [i.asString, Color.white, Color.red]])
            .value_(if (currentSurvival.includes(i)) { 1 } { 0 })
            .action_({ |btn|
                toggleNeighbor.(i, false);
            });

        if ((i % 8) == 7) { ruleEditorView.decorator.nextLine };
    };

    ruleEditorView.decorator.nextLine;

    StaticText(ruleEditorView, (ruleEditorView.bounds.width-10)@20)
        .string_("Current: B" ++ currentBirth.join(",") ++ "/S" ++ currentSurvival.join(","))
        .font_(Font.default.size_(12))
        .align_(\center);
};

var updateGrid = {
    var newGrid;

    if (dimensions == 1) {
        newGrid = Array.fill(gridSize, { |x|
            var neighbors = countNeighbors.(x);
            applyRule.(grid[x], neighbors);
        });
    } {
        if (dimensions == 2) {
            newGrid = Array.fill(gridSize, { |x|
                Array.fill(gridSize, { |y|
                    var neighbors = countNeighbors.(x, y);
                    applyRule.(grid[x][y], neighbors);
                });
            });
        } {
            if (dimensions == 3) {
                newGrid = Array.fill(gridSize, { |x|
                    Array.fill(gridSize, { |y|
                        Array.fill(gridSize, { |z|
                            var neighbors = countNeighbors.(x, y, z);
                            applyRule.(grid[x][y][z], neighbors);
                        });
                    });
                });
            }
        }
    };

    grid = newGrid;
    generation = generation + 1;

    { updateStatus.() }.defer;
    playSounds.();
};

var getActiveCells = {
    var activeCells = List.new;

    if (dimensions == 1) {
        gridSize.do { |x|
            if (grid[x] > 0) {
                activeCells.add([x]);
            };
        };
    } {
        if (dimensions == 2) {
            gridSize.do { |x|
                gridSize.do { |y|
                    if (grid[x][y] > 0) {
                        activeCells.add([x, y]);
                    };
                };
            };
        } {
            if (dimensions == 3) {
                gridSize.do { |x|
                    gridSize.do { |y|
                        gridSize.do { |z|
                            if (grid[x][y][z] > 0) {
                                activeCells.add([x, y, z]);
                            };
                        };
                    };
                };
            }
        }
    };

    activeCells;
};

var calculateFrequency = { |coords|
    var freq = baseFreq;
    var axes = [\x, \y, \z];

    coords.do { |coord, i|
        if (i < axes.size) {
            var ratio = harmonicRatios[axes[i]];
            var r = (ratio[0] / ratio[1]) ** coord;
            freq = freq * r;
        };
    };

    freq;
};

var coordsToKey = { |coords|
    coords.join("_");
};

var keyToCoords = { |key|
    key.split($_).collect(_.asInteger);
};

var playSounds = {
    var activeCells = getActiveCells.();

    if (arpeggiate && (activeCells.size > 1)) {
        playArpeggiated.(activeCells);
    } {
        playSimultaneous.(activeCells);
    };
};

var playSimultaneous = { |activeCells|
    var currentVoiceIds, newVoiceIds, toStop, toStart;
    var masterAmp;

    "Playing % active cells simultaneously".format(activeCells.size).postln;

    if (arpeggiator.notNil) {
        arpeggiator.stop;
        arpeggiator = nil;
    };

    currentVoiceIds = Set.newFrom(activeVoices.keys);
    newVoiceIds = Set.newFrom(activeCells.collect({ |coords| coordsToKey.(coords) }));

    toStop = currentVoiceIds - newVoiceIds;
    toStop.do { |voiceId|
        activeVoices[voiceId].set(\gate, 0);
        activeVoices.removeAt(voiceId);
    };

    masterAmp = 0.8 / (activeCells.size.max(1).sqrt);

    toStart = newVoiceIds - currentVoiceIds;
    toStart.do { |voiceId|
        var coords = keyToCoords.(voiceId);
        var freq = calculateFrequency.(coords);
        var pan = ((coords[0] ? 0) - (gridSize / 2)) / (gridSize / 2) * 0.5;
        var filterFreq = freq * 3;

        if (toStart.size < 4) {
            "Starting voice %: coords=%, freq=%Hz, amp=%".format(voiceId, coords, freq.round(0.1), masterAmp.round(0.01)).postln;
        };

        activeVoices[voiceId] = Synth(\caHarmonic, [
            \freq, freq,
            \amp, masterAmp,
            \pan, pan,
            \filterFreq, filterFreq,
            \filterQ, 2,
            \attack, 0.05,
            \release, 0.2
        ], Server.default);
    };
};

var playArpeggiated = { |activeCells|
    var sortedCells, pattern, cellFreqPairs;
    var noteTime, attack, release, totalTime;

    activeVoices.keysValuesDo { |key, synth|
        synth.set(\gate, 0);
    };
    activeVoices.clear;

    if (arpeggiator.notNil) {
        arpeggiator.stop;
    };

    if (activeCells.size == 0) { ^this };

    totalTime = generationTime * 0.95;
    noteTime = totalTime / activeCells.size;

    attack = (noteTime * 0.1).max(0.01);
    release = (noteTime * 0.3).max(0.02);

    cellFreqPairs = activeCells.collect({ |coords|
        [calculateFrequency.(coords), coords]
    });

    cellFreqPairs.sort({ |a, b| a[0] <= b[0] });

    sortedCells = cellFreqPairs.collect({ |pair| pair[1] });

    switch(arpPattern,
        \up, {
        },
        \down, {
            sortedCells = sortedCells.reverse;
        },
        \updown, {
            if (sortedCells.size > 2) {
                sortedCells = sortedCells ++ sortedCells[1..(sortedCells.size-2)].reverse;
                noteTime = totalTime / sortedCells.size;
                attack = (noteTime * 0.1).max(0.01);
                release = (noteTime * 0.3).max(0.02);
            };
        },
        \random, {
            sortedCells = sortedCells.scramble;
        }
    );

    pattern = Pbind(
        \instrument, \caArp,
        \freq, Pseq(sortedCells.collect({ |coords| calculateFrequency.(coords) }), inf),
        \dur, noteTime,
        \attack, attack,
        \release, release,
        \amp, Pexprand(0.08, 0.15, inf),
        \pan, Pseq(sortedCells.collect({ |coords|
            ((coords[0] ? 0) - (gridSize / 2)) / (gridSize / 2) * 0.7
        }), inf),
        \filterFreq, Pseq(sortedCells.collect({ |coords|
            var freq = calculateFrequency.(coords);
            freq * (2.5 + (coords[1] ? 0 / gridSize))
        }), inf),
        \cellX, Pseq(sortedCells.collect({ |coords| coords[0] ? 0 }), inf),
        \cellY, Pseq(sortedCells.collect({ |coords| coords[1] ? 0 }), inf),
        \cellZ, Pseq(sortedCells.collect({ |coords| coords[2] ? 0 }), inf),
        \server, Server.default
    );

    arpeggiator = pattern.play;
};

var stopAllSounds = {
    Server.default.freeAll;
    activeVoices.clear;
    if (arpeggiator.notNil) {
        arpeggiator.stop;
        arpeggiator = nil;
    };
};

var start = {
    if (running.not) {
        "Starting CA evolution...".postln;
        running = true;
        updateTask = Task({
            loop {
                if (running) {
                    updateGrid.();
                };
                generationTime.wait;
            };
        }).play;

        playSounds.();
        "CA started with % active cells".format(getActiveCells.().size).postln;
    };
};

var stop = {
    running = false;
    if (updateTask.notNil) {
        updateTask.stop;
        updateTask = nil;
    };
    stopAllSounds.();
};

var step = {
    updateGrid.();
};

var reset = {
    initializeGrid.();
    playSounds.();
};

var updateStatus = {
    var activeCells = getActiveCells.();
    var ruleString = "B" ++ currentBirth.join(",") ++ "/S" ++ currentSurvival.join(",");

    if (statusText.notNil) {
        statusText.string = "Generation: % | Active Cells: % | Rule: % | %D | Grid: %x%".format(
            generation, activeCells.size, ruleString, dimensions, gridSize, gridSize
        );
    };
};

var createGUI = {
    var windowWidth = 450, windowHeight = 620;
    var dimSlider, sizeSlider, timeSlider, densitySlider;
    var dimText, sizeText, timeText, densityText;
    var transportView, ratioView, freqBox, arpCheck;
    var numBox, denBox, ruleMenu;
    var ruleKeys = [\conway, \fredkin, \brain, \seeds, \daynight];
    var conwayIndex;

    window = Window("Cellular Automata in Harmonic Space", Rect(100, 100, windowWidth, windowHeight));
    window.view.decorator = FlowLayout(window.view.bounds, 10@10, 5@5);

    StaticText(window, (windowWidth-20)@25)
        .string_("Cellular Automata in Harmonic Space")
        .align_(\center)
        .font_(Font.default.size_(16));

    window.view.decorator.nextLine;

    leftColumn = CompositeView(window, (windowWidth-20)@(windowHeight-80));
    leftColumn.decorator = FlowLayout(leftColumn.bounds, 5@5, 3@3);

    transportView = CompositeView(leftColumn, (windowWidth-30)@40);
    transportView.decorator = FlowLayout(transportView.bounds);

    Button(transportView, 110@35).states_([["▶ Start"], ["⏸ Stop"]])
        .action_({ |btn| if (btn.value == 1) { start.() } { stop.() } });

    Button(transportView, 110@35).states_([["⏭ Step"]])
        .action_({ step.() });

    Button(transportView, 110@35).states_([["🔄 Reset"]])
        .action_({ reset.() });

    leftColumn.decorator.nextLine;
    leftColumn.decorator.nextLine;

    StaticText(leftColumn, 80@20).string_("Dimensions:");
    dimSlider = Slider(leftColumn, 200@20).value_(0.5).action_({ |sl|
        var newDim = (sl.value * 2 + 1).round.asInteger;
        if (newDim != dimensions) {
            stop.();
            dimensions = newDim;

            if (dimensions == 1) {
                currentRule = \brain;
                loadRuleIntoEditor.();
                { ruleMenu.value = 2; }.defer;
                "Auto-switched to Brian's Brain for 1D".postln;
            } {
                if (dimensions == 2) {
                    if (currentRule == \brain || currentRule == \fredkin) {
                        currentRule = \conway;
                        loadRuleIntoEditor.();
                        { ruleMenu.value = 0; }.defer;
                        "Auto-switched to GoL for 2D".postln;
                    };
                } {
                    if (dimensions == 3) {
                        currentRule = \fredkin;
                        loadRuleIntoEditor.();
                        if (gridSize > 8) {
                            gridSize = 8;
                            sizeSlider.value = (gridSize - 4) / 12;
                            sizeText.string = gridSize.asString;
                        };
                        { ruleMenu.value = 1; }.defer;
                        "Auto-switched to Fredkin for 3D".postln;
                    }
                }
            };

            initializeGrid.();
            updateStatus.();
            dimText.string = dimensions.asString ++ "D";
        };
    });
    dimText = StaticText(leftColumn, 50@20).string_(dimensions.asString ++ "D");
    leftColumn.decorator.nextLine;

    StaticText(leftColumn, 80@20).string_("Grid Size:");
    sizeSlider = Slider(leftColumn, 200@20).value_(0.33).action_({ |sl|
        var maxSize = if (dimensions == 3) { 8 } { 16 };
        var newSize = (sl.value * (maxSize - 4) + 4).round.asInteger;
        if (newSize != gridSize) {
            stop.();
            gridSize = newSize;

            initializeGrid.();
            updateStatus.();
            sizeText.string = gridSize.asString;
            "Grid size changed to %x%".format(gridSize, gridSize).postln;
        };
    });
    sizeText = StaticText(leftColumn, 50@20).string_(gridSize.asString);
    leftColumn.decorator.nextLine;

    StaticText(leftColumn, 80@20).string_("Rule:");
    conwayIndex = ruleKeys.indexOf(\conway);
    ruleMenu = PopUpMenu(leftColumn, 250@20).items_(ruleKeys.collect({ |k| rules[k][\name] }))
        .value_(conwayIndex)
        .action_({ |menu|
            currentRule = ruleKeys[menu.value];

            loadRuleIntoEditor.();

            initializeGrid.();
            updateStatus.();
        });
    leftColumn.decorator.nextLine;

    StaticText(leftColumn, 80@20).string_("Gen Time:");
    timeSlider = Slider(leftColumn, 200@20).value_(0.1).action_({ |sl|
        generationTime = sl.value * 4 + 0.1;
        timeText.string = (generationTime.round(0.1)).asString ++ "s";
    });
    timeText = StaticText(leftColumn, 100@20).string_((generationTime.round(0.1)).asString ++ "s");
    leftColumn.decorator.nextLine;

    StaticText(leftColumn, 80@20).string_("Init Density:");
    densitySlider = Slider(leftColumn, 200@20).value_(initDensity).action_({ |sl|
        initDensity = sl.value;
        densityText.string = (initDensity * 100).round(1).asString ++ "%";
    });
    densityText = StaticText(leftColumn, 50@20).string_((initDensity * 100).round(1).asString ++ "%");
    leftColumn.decorator.nextLine;
    leftColumn.decorator.nextLine;

    createRuleEditor.(leftColumn);
    leftColumn.decorator.nextLine;

    [\x, \y, \z].do { |axis, index|
        var currentAxis = axis;
        var currentNumBox, currentDenBox;

        ratioView = CompositeView(leftColumn, (windowWidth-30)@25);
        ratioView.decorator = FlowLayout(ratioView.bounds);

        StaticText(ratioView, 20@20).string_(currentAxis.asString.toUpper);
        currentNumBox = NumberBox(ratioView, 40@20).value_(harmonicRatios[currentAxis][0]);
        StaticText(ratioView, 10@20).string_("/");
        currentDenBox = NumberBox(ratioView, 40@20).value_(harmonicRatios[currentAxis][1]);
        Button(ratioView, 40@20).states_([["Set"]])
            .action_({
                var newNum = currentNumBox.value.asInteger.max(1);
                var newDen = currentDenBox.value.asInteger.max(1);
                var newRatio = newNum / newDen;

                harmonicRatios.put(currentAxis, [newNum, newDen]);

                ("Updated " ++ currentAxis ++ " ratio to " ++ newNum ++ "/" ++ newDen ++ " = " ++ newRatio).postln;
                ("Current ratios: X=" ++ (harmonicRatios[\x][0]/harmonicRatios[\x][1]) ++
                 ", Y=" ++ (harmonicRatios[\y][0]/harmonicRatios[\y][1]) ++
                 ", Z=" ++ (harmonicRatios[\z][0]/harmonicRatios[\z][1])).postln;

                Server.default.freeAll;
                activeVoices.clear;
                if (arpeggiator.notNil) { arpeggiator.stop; arpeggiator = nil; };

                {
                    if (getActiveCells.().size == 0) { initializeGrid.(); };
                    playSounds.();
                }.defer(0.5);
            });
    };

    leftColumn.decorator.nextLine;

    StaticText(leftColumn, 80@20).string_("Origin Freq:");
    freqBox = NumberBox(leftColumn, 60@20).value_(baseFreq).action_({ |box|
        baseFreq = box.value;
        stopAllSounds.();
        { playSounds.() }.defer(0.1);
    });
    StaticText(leftColumn, 20@20).string_("Hz");
    leftColumn.decorator.nextLine;

    arpCheck = CheckBox(leftColumn, 100@20).string_("Arpeggiate").value_(arpeggiate)
        .action_({ |cb| arpeggiate = cb.value; playSounds.(); });

    PopUpMenu(leftColumn, 150@20).items_([\up, \down, \updown, \random])
        .action_({ |menu|
            arpPattern = [\up, \down, \updown, \random][menu.value];
            if (arpeggiate) { playSounds.() };
        });
    leftColumn.decorator.nextLine;

    leftColumn.decorator.nextLine;
    leftColumn.decorator.nextLine;

    statusText = StaticText(leftColumn, (windowWidth-30)@40).string_("Ready");

    window.front;
    window.onClose_({
        stop.();
    });

    updateStatus.();
};

{
    var serverOptions = ServerOptions.new;
    serverOptions.numInputBusChannels = 0;
    serverOptions.numOutputBusChannels = 2;
    serverOptions.sampleRate = 48000;
    serverOptions.blockSize = 64;
    Server.default.options = serverOptions;

    if (Server.default.serverRunning.not) {
        "Booting audio server...".postln;
        Server.default.boot;
        Server.default.waitForBoot({
            "Server ready, initializing CA...".postln;
            init.();
            0.5.wait;
            { createGUI.() }.defer;
        });
    } {
        "Server already running, initializing CA...".postln;
        init.();
        0.5.wait;
        { createGUI.() }.defer;
    };
}.fork;

"CA HS loading...".postln;
)