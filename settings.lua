data:extend({
    {
        type = 'int-setting',
        name = 'mts-expanse-cell-size',
        setting_type = 'startup',
        default_value = 15,
        minimum_value = 8,
        maximum_value = 64,
        order = 'a-a'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-token-chance',
        setting_type = 'runtime-global',
        default_value = 0.20,
        minimum_value = 0,
        maximum_value = 10,
        order = 'b-a'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-price-distance-modifier',
        setting_type = 'runtime-global',
        default_value = 0.006,
        minimum_value = 0.0001,
        maximum_value = 1,
        order = 'b-b'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-max-ore-price-modifier',
        setting_type = 'runtime-global',
        default_value = 0.33,
        minimum_value = 0,
        maximum_value = 10,
        order = 'b-c'
    },
    {
        type = 'bool-setting',
        name = 'mts-expanse-override-nauvis',
        setting_type = 'runtime-global',
        default_value = true,
        order = 'b-d'
    },
    {
        type = 'bool-setting',
        name = 'mts-expanse-cleanup-mts-nauvis',
        setting_type = 'runtime-global',
        default_value = true,
        order = 'b-e'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-admin-open-max-radius',
        setting_type = 'runtime-global',
        default_value = 8,
        minimum_value = 0,
        maximum_value = 64,
        order = 'c-a'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-admin-frontier-max-rings',
        setting_type = 'runtime-global',
        default_value = 4,
        minimum_value = 1,
        maximum_value = 64,
        order = 'c-b'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-admin-frontier-max-cells',
        setting_type = 'runtime-global',
        default_value = 256,
        minimum_value = 1,
        maximum_value = 10000,
        order = 'c-c'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-cell-value-multiplier',
        setting_type = 'runtime-global',
        default_value = 8,
        minimum_value = 0.1,
        maximum_value = 100,
        order = 'd-a'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-min-cell-value',
        setting_type = 'runtime-global',
        default_value = 16,
        minimum_value = 1,
        maximum_value = 100000,
        order = 'd-b'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-fluid-price-multiplier',
        setting_type = 'runtime-global',
        default_value = 0.01,
        minimum_value = 0,
        maximum_value = 10,
        order = 'd-c'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-ore-modifier-divisor',
        setting_type = 'runtime-global',
        default_value = 20,
        minimum_value = 1,
        maximum_value = 10000,
        order = 'd-d'
    },
    {
        type = 'string-setting',
        name = 'mts-expanse-tier-distance-thresholds',
        setting_type = 'runtime-global',
        default_value = '30,60,90,150,210,300',
        allow_blank = false,
        order = 'd-e'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-price-roll-count',
        setting_type = 'runtime-global',
        default_value = 3,
        minimum_value = 1,
        maximum_value = 20,
        order = 'd-f'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-tier10-special-chance',
        setting_type = 'runtime-global',
        default_value = 20,
        minimum_value = 1,
        maximum_value = 1000,
        order = 'd-g'
    },
    {
        type = 'bool-setting',
        name = 'mts-expanse-sync-cell-content',
        setting_type = 'runtime-global',
        default_value = true,
        order = 'd-h'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-map-starting-area',
        setting_type = 'runtime-global',
        default_value = 0.08,
        minimum_value = 0,
        maximum_value = 10,
        order = 'e-a'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-spoil-time-modifier',
        setting_type = 'runtime-global',
        default_value = 1,
        minimum_value = 0.01,
        maximum_value = 100,
        order = 'e-b'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-enemy-expansion-cooldown-ticks',
        setting_type = 'runtime-global',
        default_value = 1800,
        minimum_value = 1,
        maximum_value = 216000,
        order = 'e-c'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-enemy-settler-group-max-size',
        setting_type = 'runtime-global',
        default_value = 8,
        minimum_value = 0,
        maximum_value = 1000,
        order = 'e-d'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-enemy-settler-group-min-size',
        setting_type = 'runtime-global',
        default_value = 16,
        minimum_value = 0,
        maximum_value = 1000,
        order = 'e-e'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-enemy-evolution-destroy-factor',
        setting_type = 'runtime-global',
        default_value = 0.003,
        minimum_value = 0,
        maximum_value = 1,
        order = 'e-f'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-enemy-evolution-pollution-factor',
        setting_type = 'runtime-global',
        default_value = 0.0000006,
        minimum_value = 0,
        maximum_value = 1,
        order = 'e-g'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-enemy-evolution-time-factor',
        setting_type = 'runtime-global',
        default_value = 0.000002,
        minimum_value = 0,
        maximum_value = 1,
        order = 'e-h'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-map-reset-delay-ticks',
        setting_type = 'runtime-global',
        default_value = 7200,
        minimum_value = 1,
        maximum_value = 216000,
        order = 'e-i'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-space-production-interval-ticks',
        setting_type = 'runtime-global',
        default_value = 3600,
        minimum_value = 1,
        maximum_value = 216000,
        order = 'e-j'
    },
    {
        type = 'bool-setting',
        name = 'mts-expanse-invasion-enabled',
        setting_type = 'runtime-global',
        default_value = true,
        order = 'f-a'
    },
    {
        type = 'bool-setting',
        name = 'mts-expanse-sync-invasions',
        setting_type = 'runtime-global',
        default_value = true,
        order = 'f-b'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-spawner-spawn-base',
        setting_type = 'runtime-global',
        default_value = 4,
        minimum_value = 0,
        maximum_value = 1000,
        order = 'f-c'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-spawner-spawn-evolution-scale',
        setting_type = 'runtime-global',
        default_value = 8,
        minimum_value = 0,
        maximum_value = 1000,
        order = 'f-d'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-invasion-candidate-base',
        setting_type = 'runtime-global',
        default_value = 3,
        minimum_value = 1,
        maximum_value = 1000,
        order = 'f-e'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-invasion-candidate-evolution-scale',
        setting_type = 'runtime-global',
        default_value = 10,
        minimum_value = 0,
        maximum_value = 1000,
        order = 'f-f'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-invasion-group-base',
        setting_type = 'runtime-global',
        default_value = 1,
        minimum_value = 1,
        maximum_value = 1000,
        order = 'f-g'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-invasion-group-evolution-scale',
        setting_type = 'runtime-global',
        default_value = 4,
        minimum_value = 0,
        maximum_value = 1000,
        order = 'f-h'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-invasion-detonate-delay-ticks',
        setting_type = 'runtime-global',
        default_value = 7200,
        minimum_value = 1,
        maximum_value = 216000,
        order = 'f-h'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-invasion-first-warning-delay-ticks',
        setting_type = 'runtime-global',
        default_value = 120,
        minimum_value = 0,
        maximum_value = 216000,
        order = 'f-i'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-invasion-extra-warning-1-ticks',
        setting_type = 'runtime-global',
        default_value = 3600,
        minimum_value = 0,
        maximum_value = 216000,
        order = 'f-j'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-invasion-extra-warning-2-ticks',
        setting_type = 'runtime-global',
        default_value = 5400,
        minimum_value = 0,
        maximum_value = 216000,
        order = 'f-k'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-invasion-nuke-kill-radius',
        setting_type = 'runtime-global',
        default_value = 8,
        minimum_value = 0,
        maximum_value = 128,
        order = 'f-l'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-invasion-nuke-damage-radius',
        setting_type = 'runtime-global',
        default_value = 16,
        minimum_value = 0,
        maximum_value = 256,
        order = 'f-m'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-invasion-nuke-damage-fraction',
        setting_type = 'runtime-global',
        default_value = 0.75,
        minimum_value = 0,
        maximum_value = 100,
        order = 'f-n'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-invasion-biter-base',
        setting_type = 'runtime-global',
        default_value = 5,
        minimum_value = 0,
        maximum_value = 1000,
        order = 'f-o'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-invasion-biter-evolution-scale',
        setting_type = 'runtime-global',
        default_value = 30,
        minimum_value = 0,
        maximum_value = 1000,
        order = 'f-p'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-invasion-biter-round-scale',
        setting_type = 'runtime-global',
        default_value = 5,
        minimum_value = 0,
        maximum_value = 1000,
        order = 'f-q'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-invasion-worm-base',
        setting_type = 'runtime-global',
        default_value = 3,
        minimum_value = 0,
        maximum_value = 1000,
        order = 'f-r'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-invasion-worm-evolution-scale',
        setting_type = 'runtime-global',
        default_value = 7,
        minimum_value = 0,
        maximum_value = 1000,
        order = 'f-s'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-invasion-rounds-base',
        setting_type = 'runtime-global',
        default_value = 4,
        minimum_value = 0,
        maximum_value = 1000,
        order = 'f-t'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-invasion-rounds-random-max',
        setting_type = 'runtime-global',
        default_value = 8,
        minimum_value = 0,
        maximum_value = 1000,
        order = 'f-u'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-invasion-wave-first-delay-ticks',
        setting_type = 'runtime-global',
        default_value = 120,
        minimum_value = 0,
        maximum_value = 216000,
        order = 'f-v'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-invasion-wave-interval-ticks',
        setting_type = 'runtime-global',
        default_value = 300,
        minimum_value = 1,
        maximum_value = 216000,
        order = 'f-w'
    },
    {
        type = 'double-setting',
        name = 'mts-expanse-invasion-attack-radius',
        setting_type = 'runtime-global',
        default_value = 80,
        minimum_value = 1,
        maximum_value = 1024,
        order = 'f-x'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-invasion-render-grace-ticks',
        setting_type = 'runtime-global',
        default_value = 120,
        minimum_value = 0,
        maximum_value = 216000,
        order = 'f-y'
    },
    {
        type = 'bool-setting',
        name = 'mts-expanse-use-space-platform',
        setting_type = 'runtime-global',
        default_value = false,
        order = 'g-a'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-nonspace-support-size',
        setting_type = 'runtime-global',
        default_value = 40,
        minimum_value = 16,
        maximum_value = 512,
        order = 'g-b'
    },
    {
        type = 'int-setting',
        name = 'mts-expanse-rocket-launch-weight-threshold',
        setting_type = 'runtime-global',
        default_value = 999500,
        minimum_value = 0,
        maximum_value = 1000000000,
        order = 'g-c'
    }
})
