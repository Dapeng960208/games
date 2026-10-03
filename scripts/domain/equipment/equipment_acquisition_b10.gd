extends RefCounted
## Immutable B10 acquisition-v5 archive. Existing receipts retain v1-v4.
const LEVEL_CAP := 50
const TEMPLATES := {
  "B10-SW-head": {
    "slot": "head",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "max_hp",
        "armor"
      ]
    },
    "price": 140,
    "allowed_heroes": [
      "CH01"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SW",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SW-chest": {
    "slot": "chest",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "max_hp",
        "armor"
      ]
    },
    "price": 180,
    "allowed_heroes": [
      "CH01"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SW",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SW-hands": {
    "slot": "hands",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "attack",
        "crit_chance"
      ]
    },
    "price": 120,
    "allowed_heroes": [
      "CH01"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SW",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SW-legs": {
    "slot": "legs",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "max_hp",
        "armor",
        "magic_resist"
      ]
    },
    "price": 180,
    "allowed_heroes": [
      "CH01"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SW",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SW-feet": {
    "slot": "feet",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "move_speed",
        "damage_reduction"
      ]
    },
    "price": 120,
    "allowed_heroes": [
      "CH01"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SW",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SW-ring": {
    "slot": "ring",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "attack",
        "resource_gain_bonus"
      ]
    },
    "price": 160,
    "allowed_heroes": [
      "CH01"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SW",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SW-accessory": {
    "slot": "charm",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "resource_gain_bonus",
        "max_hp"
      ]
    },
    "price": 160,
    "allowed_heroes": [
      "CH01"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SW",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SW-weapon": {
    "slot": "weapon",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "attack",
        "damage_bonus"
      ]
    },
    "price": 180,
    "allowed_heroes": [
      "CH01"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SW",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SG-head": {
    "slot": "head",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "max_hp",
        "crit_chance"
      ]
    },
    "price": 140,
    "allowed_heroes": [
      "CH02"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SG",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SG-chest": {
    "slot": "chest",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "max_hp",
        "armor"
      ]
    },
    "price": 180,
    "allowed_heroes": [
      "CH02"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SG",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SG-hands": {
    "slot": "hands",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "attack",
        "crit_chance"
      ]
    },
    "price": 120,
    "allowed_heroes": [
      "CH02"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SG",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SG-legs": {
    "slot": "legs",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "max_hp",
        "armor",
        "magic_resist"
      ]
    },
    "price": 180,
    "allowed_heroes": [
      "CH02"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SG",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SG-feet": {
    "slot": "feet",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "move_speed"
      ]
    },
    "price": 120,
    "allowed_heroes": [
      "CH02"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SG",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SG-ring": {
    "slot": "ring",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "attack",
        "crit_chance"
      ]
    },
    "price": 160,
    "allowed_heroes": [
      "CH02"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SG",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SG-accessory": {
    "slot": "charm",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "damage_bonus",
        "max_hp"
      ]
    },
    "price": 160,
    "allowed_heroes": [
      "CH02"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SG",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SG-weapon": {
    "slot": "weapon",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "attack",
        "damage_bonus"
      ]
    },
    "price": 180,
    "allowed_heroes": [
      "CH02"
    ],
    "power_types": [
      "physical"
    ],
    "set_id": "B10-SG",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SM-head": {
    "slot": "head",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "magic": [
        "max_mana",
        "magic_resist"
      ]
    },
    "price": 140,
    "allowed_heroes": [
      "CH03"
    ],
    "power_types": [
      "magic"
    ],
    "set_id": "B10-SM",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SM-chest": {
    "slot": "chest",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "magic": [
        "max_hp",
        "magic_resist"
      ]
    },
    "price": 180,
    "allowed_heroes": [
      "CH03"
    ],
    "power_types": [
      "magic"
    ],
    "set_id": "B10-SM",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SM-hands": {
    "slot": "hands",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "magic": [
        "ability_power",
        "cooldown_reduction"
      ]
    },
    "price": 120,
    "allowed_heroes": [
      "CH03"
    ],
    "power_types": [
      "magic"
    ],
    "set_id": "B10-SM",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SM-legs": {
    "slot": "legs",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "magic": [
        "max_hp",
        "armor",
        "magic_resist"
      ]
    },
    "price": 180,
    "allowed_heroes": [
      "CH03"
    ],
    "power_types": [
      "magic"
    ],
    "set_id": "B10-SM",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SM-feet": {
    "slot": "feet",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "magic": [
        "move_speed"
      ]
    },
    "price": 120,
    "allowed_heroes": [
      "CH03"
    ],
    "power_types": [
      "magic"
    ],
    "set_id": "B10-SM",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SM-ring": {
    "slot": "ring",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "magic": [
        "ability_power",
        "resource_gain_bonus"
      ]
    },
    "price": 160,
    "allowed_heroes": [
      "CH03"
    ],
    "power_types": [
      "magic"
    ],
    "set_id": "B10-SM",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SM-accessory": {
    "slot": "charm",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "magic": [
        "max_mana",
        "max_hp"
      ]
    },
    "price": 160,
    "allowed_heroes": [
      "CH03"
    ],
    "power_types": [
      "magic"
    ],
    "set_id": "B10-SM",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SM-weapon": {
    "slot": "weapon",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "magic": [
        "ability_power",
        "damage_bonus"
      ]
    },
    "price": 180,
    "allowed_heroes": [
      "CH03"
    ],
    "power_types": [
      "magic"
    ],
    "set_id": "B10-SM",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SU-head": {
    "slot": "head",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "max_hp",
        "magic_resist"
      ],
      "magic": [
        "max_hp",
        "magic_resist"
      ]
    },
    "price": 140,
    "allowed_heroes": [
      "CH01",
      "CH02",
      "CH03"
    ],
    "power_types": [
      "physical",
      "magic"
    ],
    "set_id": "B10-SU",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SU-chest": {
    "slot": "chest",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "max_hp",
        "damage_reduction"
      ],
      "magic": [
        "max_hp",
        "damage_reduction"
      ]
    },
    "price": 180,
    "allowed_heroes": [
      "CH01",
      "CH02",
      "CH03"
    ],
    "power_types": [
      "physical",
      "magic"
    ],
    "set_id": "B10-SU",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SU-hands": {
    "slot": "hands",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "attack",
        "cooldown_reduction"
      ],
      "magic": [
        "ability_power",
        "cooldown_reduction"
      ]
    },
    "price": 120,
    "allowed_heroes": [
      "CH01",
      "CH02",
      "CH03"
    ],
    "power_types": [
      "physical",
      "magic"
    ],
    "set_id": "B10-SU",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SU-legs": {
    "slot": "legs",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "max_hp",
        "armor",
        "magic_resist"
      ],
      "magic": [
        "max_hp",
        "armor",
        "magic_resist"
      ]
    },
    "price": 180,
    "allowed_heroes": [
      "CH01",
      "CH02",
      "CH03"
    ],
    "power_types": [
      "physical",
      "magic"
    ],
    "set_id": "B10-SU",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SU-feet": {
    "slot": "feet",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "move_speed",
        "damage_reduction"
      ],
      "magic": [
        "move_speed",
        "damage_reduction"
      ]
    },
    "price": 120,
    "allowed_heroes": [
      "CH01",
      "CH02",
      "CH03"
    ],
    "power_types": [
      "physical",
      "magic"
    ],
    "set_id": "B10-SU",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SU-ring": {
    "slot": "ring",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "attack",
        "max_hp"
      ],
      "magic": [
        "ability_power",
        "max_hp"
      ]
    },
    "price": 160,
    "allowed_heroes": [
      "CH01",
      "CH02",
      "CH03"
    ],
    "power_types": [
      "physical",
      "magic"
    ],
    "set_id": "B10-SU",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SU-accessory": {
    "slot": "charm",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "max_hp",
        "damage_reduction",
        "cooldown_reduction"
      ],
      "magic": [
        "max_hp",
        "damage_reduction",
        "cooldown_reduction"
      ]
    },
    "price": 160,
    "allowed_heroes": [
      "CH01",
      "CH02",
      "CH03"
    ],
    "power_types": [
      "physical",
      "magic"
    ],
    "set_id": "B10-SU",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-SU-weapon": {
    "slot": "weapon",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "attack"
      ],
      "magic": [
        "ability_power"
      ]
    },
    "price": 180,
    "allowed_heroes": [
      "CH01",
      "CH02",
      "CH03"
    ],
    "power_types": [
      "physical",
      "magic"
    ],
    "set_id": "B10-SU",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-U01": {
    "slot": "feet",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "move_speed",
        "damage_reduction"
      ],
      "magic": [
        "move_speed",
        "damage_reduction"
      ]
    },
    "price": 120,
    "allowed_heroes": [
      "CH01",
      "CH02",
      "CH03"
    ],
    "power_types": [
      "physical",
      "magic"
    ],
    "set_id": "",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-U02": {
    "slot": "ring",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "attack",
        "max_hp"
      ],
      "magic": [
        "ability_power",
        "max_hp"
      ]
    },
    "price": 160,
    "allowed_heroes": [
      "CH01",
      "CH02",
      "CH03"
    ],
    "power_types": [
      "physical",
      "magic"
    ],
    "set_id": "",
    "drop_origin": "B10",
    "class_policy_version": 4
  },
  "B10-U03": {
    "slot": "charm",
    "race_id": "B10",
    "affix_tendencies_by_power": {
      "physical": [
        "max_hp",
        "damage_reduction",
        "cooldown_reduction"
      ],
      "magic": [
        "max_hp",
        "damage_reduction",
        "cooldown_reduction"
      ]
    },
    "price": 160,
    "allowed_heroes": [
      "CH01",
      "CH02",
      "CH03"
    ],
    "power_types": [
      "physical",
      "magic"
    ],
    "set_id": "",
    "drop_origin": "B10",
    "class_policy_version": 4
  }
}
const PREFERENCE_WEIGHT := 2
const ROOM_PREFERRED_SLOTS := {"L55": ["head", "chest"], "L56": ["legs", "feet"], "L57": ["hands", "ring"], "L58": ["hands", "ring"], "L59": ["weapon", "charm"], "L60": ["weapon", "charm"], "BO10": ["weapon", "charm"]}
const ROOM_LEVELS := {"L55": 46, "L56": 46, "L57": 48, "L58": 48, "L59": 50, "L60": 50, "BO10": 50}
const MONSTER_PREFERRED_SLOT := {"B10-M01": "chest", "B10-M02": "feet", "B10-M03": "head", "B10-M04": "hands", "B10-M05": "ring", "B10-M06": "chest", "B10-M07": "legs", "B10-M08": "head", "B10-M09": "weapon", "B10-M10": "charm", "B10-M11": "chest", "B10-M12": "feet", "B10-M13": "weapon", "B10-M14": "hands", "B10-M15": "ring", "B10-M16": "charm", "B10-M17": "legs", "B10-M18": "charm"}
const UNIQUE_PREFERENCES := {"B10-U01": ["L56", "B10-M02", "B10-M05"], "B10-U02": ["L58", "B10-M10", "B10-M11"], "B10-U03": ["L60", "B10-M16", "B10-M18"]}
