# Протокол межпроцессного взаимодействия (`IPC Battle Protocol`)

`Campaign Server` (`mb_warband_wse2_dedicated_campaign.exe`) и пул тактических серверов `Battle Server Pool` (`mb_warband_wse2_dedicated.exe`, слоты `0..N-1`) обмениваются структурированными конвертами через `CoopHostSupervisor` и атомарную директорию обмена `Modules/CalradiaOnline/lua/ipc/`.

Атомарность гарантируется записью во временный файл `*.tmp` с последующим атомарным `rename()` в `*.json` + монотонным `seq_id`.

---

## 1. Жизненный цикл тактической сессии (Полевой бой / Осада / Турнир / Побег)

```
Campaign Server (Lua)            CoopHostSupervisor               Battle Server Slot #K (Lua)
        │                                │                                     │
        ├── 1. BATTLE_SPAWN_REQ ────────►│                                     │
        │   (состав армий, сцена, погода)├── Выбирает свободный (или поднимает)│
        │                                │   слот #K и кладёт задание ────────►│
        │                                │                                     ├── Загружает сцену и ростеры
        │◄─ 2. BATTLE_READY ─────────────┼◄── Подтверждение готовности ────────┤
        │                                │                                     │
        ├── Отправляет клиентам          │                                     │
        │   BATTLE_REDIRECT (slot=#K)    │                                     │
        │                                │                                     │
        ├── 3. LIVE_REINFORCEMENT ──────►├────────────────────────────────────►│
        │   (если с глобальной карты в   │                                     ├── Добавляет отряд в очередь
        │    идущий бой вошёл друг/враг!)│                                     │   волн подкреплений!
        │                                │                                     │
        │◄─ 4. BATTLE_RESULT_REPORT ─────┼◄── Бой окончен / отступление ───────┤
        │   (точные потери по партиям,   │                                     │
        │    фраги героев, пленные)      │                                     │
        ├── Применяет Хирургию, XP, лут, │                                     │
        │   захват замка, сохраняет мир  │                                     │
```

---

## 2. Типы миссий (`mission_kind`)

| Код | Константа | Описание |
|---|---|---|
| `1` | `MISSION_FIELD_BATTLE` | Полевое сражение (степь, равнина, лес, горы, пустыня, снега, переправа) |
| `2` | `MISSION_SIEGE_ASSAULT` | Штурм города/замка с лестницами или осадной башней (включая улицы и цитадель) |
| `3` | `MISSION_SIEGE_DEFENSE` | Оборона осаждённого замка/города игроком против армии ИИ или других игроков |
| `4` | `MISSION_VILLAGE_RAID` | Сражение в деревне (грабёж, защита крестьян, бой с бандитами в деревне) |
| `5` | `MISSION_BANDIT_LAIR` | Зачистка логова лесных/горных/степных/морских разбойников |
| `6` | `MISSION_TOURNAMENT` | Совместный городской турнир (до 6 раундов с сеткой участников и ставками) |
| `7` | `MISSION_PRISON_BREAK` | Кооперативный побег из темницы замка/города для освобождения лорда или друга |
| `8` | `MISSION_TAVERN_DUEL` | Поединок чести за даму, дуэль между игроками или пьяная драка / убийца в таверне |

---

## 3. Структура `BATTLE_SPAWN_REQ`

```json
{
  "msg_type": "BATTLE_SPAWN_REQ",
  "seq_id": 1042,
  "battle_id": 17,
  "mission_kind": 1,
  "scene_id": "scn_random_scene_plain",
  "terrain_seed": 884120,
  "time_of_day": 14,
  "rain_type": 0,
  "rain_strength": 0,
  "map_pos": [42.5, -18.2],
  "center_id": -1,
  "siege_has_belfry": false,
  "sides": [
    {
      "side_index": 0,
      "faction_id": "fac_coop_player_0",
      "banner_id": 42,
      "tactics_skill": 5,
      "parties": [
        {
          "party_id": 601,
          "owner_player_uid": "p_9f82c1a0...",
          "surgery_skill": 6,
          "first_aid_skill": 4,
          "looting_skill": 3,
          "prisoner_mgmt_skill": 4,
          "stacks": [
            {"troop_id": 360, "count": 1, "wounded": 0, "is_hero": true, "hp_pct": 92},
            {"troop_id": 44, "count": 28, "wounded": 3, "is_hero": false}
          ]
        }
      ]
    },
    {
      "side_index": 1,
      "faction_id": "fac_kingdom_1",
      "banner_id": 12,
      "tactics_skill": 4,
      "parties": [
        {
          "party_id": 188,
          "owner_player_uid": null,
          "surgery_skill": 2,
          "first_aid_skill": 2,
          "looting_skill": 0,
          "prisoner_mgmt_skill": 2,
          "stacks": [
            {"troop_id": 152, "count": 1, "wounded": 0, "is_hero": true, "hp_pct": 100},
            {"troop_id": 41, "count": 54, "wounded": 0, "is_hero": false}
          ]
        }
      ]
    }
  ]
}
```

---

## 4. Структура `BATTLE_RESULT_REPORT`

```json
{
  "msg_type": "BATTLE_RESULT_REPORT",
  "seq_id": 1049,
  "battle_id": 17,
  "winning_side": 0,
  "retreated": false,
  "duration_sec": 318,
  "party_casualties": {
    "601": {
      "stacks": [
        {"troop_id": 360, "final_hp_pct": 64, "personal_kills": 9},
        {"troop_id": 44, "dead_lethal": 6, "knocked_blunt": 2, "routed": 1}
      ]
    },
    "188": {
      "stacks": [
        {"troop_id": 152, "final_hp_pct": 0, "knocked_out": true},
        {"troop_id": 41, "dead_lethal": 39, "knocked_blunt": 15, "routed": 0}
      ]
    }
  }
}
```

На стороне `Campaign Server` к `dead_lethal` каждого отряда применяется **серверная формула `Surgery`** этого отряда (`25% + 4% * surgery_skill`), переводящая спасённых бойцов из убитых в раненых, а `knocked_blunt` формирует пул доступных для захвата пленных.
