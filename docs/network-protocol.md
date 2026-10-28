# Сетевой протокол Calradia Online (WSE2 Composite Messages & UDP Mux)

Данный документ фиксирует битовый контракт между **Клиентом (`mb_warband_wse2.exe`)** и **Сервером (`Campaign Server` / `Battle Server`)**, а также заголовок однопортового мультиплексора **`CoopUdpMux`**.

> **Критический инвариант WSE2:** каждая операция `multiplayer_cur_message_get_int(dest, num_bits)` на принимающей стороне **обязана** читать ровно столько же бит (`num_bits`), сколько было записано вызовом `multiplayer_message_put_int(msg, val, num_bits)`. Все константы разрядности вынесены в `module_system/coop/coop_constants.py` и проверяются автотестом `tests/test_module_build_and_lint.py`.

---

## 1. Однопортовый транспортный уровень (`CoopUdpMux`)

Чтобы игрокам не требовалось пробрасывать диапазон портов (`7240..7250`) и не терялся пароль при прыжке `Карта <-> 3D-бой`, между `CoopClientProxy` (на ПК игрока, слушает `127.0.0.1:7240`) и `CoopHostSupervisor` (на ПК хоста, слушает внешний порт `:7240`) используется компактный 8-байтный заголовок:

| Смещение | Размер | Поле | Описание |
|---|---|---|---|
| `0` | `2 байта` | `magic` | `0x43 0x4F` (`"CO"` — Calradia Online) |
| `2` | `1 байт` | `version` | Версия транспортного протокола (`0x01`) |
| `3` | `1 байт` | `channel` | `0` = Campaign Server, `1..8` = Battle Slot `0..7`, `254` = Control/Switch, `255` = Ping/Auth |
| `4` | `4 байта` | `session_id` | Сессионный идентификатор клиента (выдаётся после проверки `identity.key`) |
| `8..N` | `N-8 байт`| `payload` | Оригинальный UDP-датаграмм движка Warband / WSE2 |

Если к хосту подключается клиент напрямую без прокси (например, локальный отладочный клиент), `CoopUdpMux` определяет отсутствие префикса `0x43 0x4F` и прозрачно проксирует датаграмму в `Campaign Server` (`channel = 0`).

---

## 2. Идентификаторы составных сообщений WSE2 (`event_no = 110..127`)

Все сообщения отправляются через `multiplayer_send_composite_message_to_server` (клиент → сервер) и `multiplayer_send_composite_message_to_player` (сервер → клиент). Первым полем внутри любого канала всегда идёт **`sub_event` (`8 бит`, `0..255`)** и **`epoch` (`16 бит`, `0..65535`)**.

### Канал `110` — `COOP_CHAN_AUTH_SESSION` (Аутентификация, профиль и вход)
| `sub_event` | Направление | Поля (`имя : биты / тип`) | Назначение |
|---|---|---|---|
| `1` (`AUTH_CHALLENGE`) | `S -> C` | `sub:8`, `epoch:16`, `nonce_str:string`, `server_flags:16` | Вызов подписи `identity.key` при подключении |
| `2` (`AUTH_RESPONSE`) | `C -> S` | `sub:8`, `epoch:16`, `player_uid:string`, `signature_hex:string`, `profile_name:string`, `face_keys:string` | Ответ клиента с криптоподписью `HMAC-SHA256(secret, nonce)` |
| `3` (`AUTH_ACCEPTED`) | `S -> C` | `sub:8`, `epoch:16`, `hero_slot:8`, `troop_id:16`, `party_id:16`, `has_existing_char:1` | Успешная привязка к слоту героя `0..31` |
| `4` (`CHAR_CREATE_SUBMIT`)| `C -> S` | `sub:8`, `epoch:16`, `gender:2`, `father:4`, `early_life:4`, `adulthood:4`, `reason:4`, `start_town_idx:4`, `friend_player_no:8`, `banner_id:10` | Отправка анкеты создания персонажа |
| `5` (`SAFE_LOGOUT_REQ`) | `C -> S` | `sub:8`, `epoch:16`, `mode:4` | Запрос безопасного выхода (запускает таймер в зоне погони) |

### Канал `111` — `COOP_CHAN_WORLD_TIME` (Время, разведка, Братства)
| `sub_event` | Направление | Поля (`имя : биты / тип`) | Назначение |
|---|---|---|---|
| `1` (`TIME_VOTE_SPEED`) | `C -> S` | `sub:8`, `epoch:16`, `desired_mode:4` (`0=Pause, 1=1x, 2=3x, 3=5x`) | Голос игрока за скорость течения времени |
| `2` (`TIME_STATE_SYNC`) | `S -> C` | `sub:8`, `epoch:16`, `effective_mode:4`, `campaign_hour:24`, `votes_fast:8`, `online_total:8` | Синхронизация текущей скорости и календаря |
| `3` (`BROTHERHOOD_OP`) | `C <-> S` | `sub:8`, `epoch:16`, `action:4` (`Invite/Accept/Leave/Kick/ShareVision`), `target_player:8` | Управление союзом (Братством) друзей |
| `4` (`CAMP_ACTION`) | `C -> S` | `sub:8`, `epoch:16`, `camp_cmd:4` (`Enter/Leave/ReadBook/RecruitPrisoners`), `arg_id:16` | Действия в полевом лагере |
| `5` (`TRACK_NODE_SYNC`) | `S -> C` | `sub:8`, `epoch:16`, `party_size:12`, `age_hours:8`, `dir_deg:9`, `flags:4`, `pos_x_cm:24`, `pos_y_cm:24` | Передача следов (`Tracking`) вокруг игрока |

### Канал `112` — `COOP_CHAN_CHAR_PARTY` (Характеристики, инвентарь, отряд, бартер)
| `sub_event` | Направление | Поля (`имя : биты / тип`) | Назначение |
|---|---|---|---|
| `1` (`CHAR_STAT_SPEND`) | `C -> S` | `sub:8`, `epoch:16`, `stat_kind:3` (`Attr/Skill/Prof`), `stat_id:8`, `amount:4` | Прокачка атрибута, навыка или оружия |
| `2` (`CHAR_SHEET_SYNC`) | `S -> C` | `sub:8`, `epoch:16`, `level:8`, `xp:32`, `gold:32`, `renown:16`, `honor_biased:16`, `rtr:8`, `free_attr:8`, `free_skill:8`, `free_prof:12` | Полная синхронизация листа персонажа (`honor_biased = honor + 10000`) |
| `3` (`INV_SLOT_SYNC`) | `S -> C` | `sub:8`, `epoch:16`, `owner_troop:16`, `slot_no:8`, `item_id:16`, `modifier:8`, `ammo_food:10` | Авторитарный пуш одного слота инвентаря/экипировки |
| `4` (`INV_SWAP_REQ`) | `C -> S` | `sub:8`, `epoch:16`, `owner_troop:16`, `from_slot:8`, `to_slot:8` | Перемещение/экипировка предмета с проверкой `epoch` |
| `5` (`PARTY_STACK_OP`) | `C -> S` | `sub:8`, `epoch:16`, `op_kind:4` (`UpgradeA/UpgradeB/Dismiss/PrisonerFree/TransferGarrison`), `stack_no:8`, `count:12` | Управление стеками войск и пленных |
| `6` (`P2P_TRADE_OP`) | `C <-> S` | `sub:8`, `epoch:16`, `trade_step:4` (`Open/SetGold/AddItem/AddTroop/Lock/Confirm/Cancel`), `arg1:16`, `arg2:16`, `gold_offer:32` | Двухфазный защищённый обмен между игроками |

### Канал `113` — `COOP_CHAN_ECONOMY_TOWNS` (Города, торговля, цеха, деревни, спутники)
| `sub_event` | Направление | Поля (`имя : биты / тип`) | Назначение |
|---|---|---|---|
| `1` (`MERCHANT_TX_REQ`) | `C -> S` | `sub:8`, `epoch:16`, `center_id:16`, `merchant_type:4`, `is_buy:1`, `slot_no:8`, `expected_item:16` | Покупка/продажа у торговца по серверной цене |
| `2` (`ENTERPRISE_OP`) | `C <-> S` | `sub:8`, `epoch:16`, `town_id:16`, `op_kind:4` (`Buy/Sell/ToggleStore`), `enterprise_type:5` | Открытие и управление городским цехом |
| `3` (`VILLAGE_OP`) | `C <-> S` | `sub:8`, `epoch:16`, `village_id:16`, `op_kind:4` (`Recruit/BuyCattle/DriveCattle/BuildImprovement/Raid`), `arg:12` | Действия в деревнях и управление стадом скота |
| `4` (`TAVERN_OP`) | `C <-> S` | `sub:8`, `epoch:16`, `town_id:16`, `op_kind:4` (`HireMercs/HireCompanion/RansomSell/RansomBuy/BuyBook/LearnPoem/BuyRound`), `arg:16` | Все взаимодействия в таверне |
| `5` (`BUDGET_REPORT`) | `S -> C` | `sub:8`, `epoch:16`, `net_delta_biased:32`, `wages:24`, `fief_income:24`, `enterprise_income:24`, `new_gold:32` | Еженедельный финансовый отчёт |

### Канал `114` — `COOP_CHAN_BATTLE_BRIDGE` (Встречи, переброска в 3D-бой, подкрепления, итоги)
| `sub_event` | Направление | Поля (`имя : биты / тип`) | Назначение |
|---|---|---|---|
| `1` (`ENCOUNTER_OPEN`) | `S -> C` | `sub:8`, `epoch:16`, `target_party:16`, `encounter_kind:6`, `can_bribe:1`, `can_talk:1`, `ally_count:12`, `enemy_count:12` | Открытие контекстного меню встречи на карте |
| `2` (`ENCOUNTER_CHOICE`) | `C -> S` | `sub:8`, `epoch:16`, `choice:5` (`Attack/AutoCalc/Bribe/Retreat/Surrender/Talk/JoinSideA/JoinSideB`) | Решение игрока при встрече / входе в идущий бой |
| `3` (`BATTLE_REDIRECT`) | `S -> C` | `sub:8`, `epoch:16`, `battle_slot:4`, `battle_id:16`, `side_no:2`, `server_addr:string`, `battle_token:string` | Команда переключения клиента на Battle-сервер |
| `4` (`DIVISION_DELEGATE`)| `C <-> S` | `sub:8`, `epoch:16`, `commander_player_no:8`, `delegate_enabled:1` | Передача/возврат права командования дивизиями в 3D-бою |
| `5` (`BATTLE_DEBRIEF`) | `S -> C` | `sub:8`, `epoch:16`, `victory:1`, `xp_gain:24`, `gold_gain:24`, `renown_gain:10`, `killed_own:12`, `wounded_saved:12`, `loot_count:8` | Сводка итогов сражения после возврата на карту |

### Канал `115` — `COOP_CHAN_QUESTS_POLITICS` (Квесты, осады, вассалитет, свадьбы, королевства)
| `sub_event` | Направление | Поля (`имя : биты / тип`) | Назначение |
|---|---|---|---|
| `1` (`QUEST_SYNC`) | `S -> C` | `sub:8`, `epoch:16`, `local_qst_slot:8`, `template_qst_id:10`, `state:4`, `giver_id:16`, `target_id:16`, `deadline_days:8`, `reward_gold:20`, `title_str:string` | Синхронизация персонального или совместного квеста |
| `2` (`QUEST_ACTION`) | `C -> S` | `sub:8`, `epoch:16`, `action:4` (`Accept/Complete/Cancel/ShareBrotherhood`), `giver_id:16`, `template_qst_id:10` | Взятие/сдача/шеринг квеста |
| `3` (`SIEGE_OP`) | `C <-> S` | `sub:8`, `epoch:16`, `center_id:16`, `op_kind:4` (`StartCamp/JoinCamp/BuildEquip/Assault/SallyOut/Lift`), `hours_left:10` | Управление осадой крепости/города |
| `4` (`POLITICS_OP`) | `C <-> S` | `sub:8`, `epoch:16`, `op_kind:6` (`MercContract/SwearOath/Renounce/FoundKingdom/GrantFief/SetMarshal/DeclareWar/OfferPeace/CourtLady/HostFeast`), `target_id:16`, `arg2:16`, `custom_name:string` | Феодальная политика, ухаживания, королевства игроков |
| `5` (`FACTION_MATRIX_SYNC`)| `S -> C`| `sub:8`, `epoch:16`, `fac_a:8`, `fac_b:8`, `rel_biased:8` (`relation + 100`) | Синхронизация дипломатических отношений на клиентах |
