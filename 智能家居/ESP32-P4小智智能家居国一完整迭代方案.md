---
created: 2026-05-28 00:00
updated: 2026-05-28 14:55
tags: [智能家居, ESP32-P4, 乐鑫赛道, 嵌入式竞赛, 国一冲刺, AIoT]
project: xiaozhi-for-p4
repo: E:\MCU\esp32\p4\xiaozhi-for-p4
---

# ESP32-P4 小智智能家居国一完整迭代方案

> [!NOTE]
> 目标不是“多做几个控制按钮”，而是把项目打磨成一个能被评委快速看懂、能现场稳定演示、能用数据证明工程质量的 AIoT 系统。当前项目方向正确，后续核心是：==可靠闭环 + 真实传感 + 多模态交互 + 答辩级可视化 + 现场兜底==。

## 0、项目最终定位

最终作品建议定位为：

**基于 ESP32-P4 + ESP32-S3 多节点协同的多模态 AIoT 智慧安全家庭中控系统**。

对应乐鑫赛道第五方向“智能交互驱动的 AIoT 应用系统”，主打以下能力：

- ESP32-P4 作为高性能中控屏，负责 LVGL HMI、语音入口、MCP 工具、设备模型、规则引擎和告警中心。
- ESP32-S3 从机作为楼层节点，负责真实外设控制、传感采集、执行 ACK 和心跳上报。
- 本地触控、小智语音/LLM、自动化规则三种入口统一到同一套 Smart Home Service。
- 主从链路使用 MQTT，必须做到命令有序列号、ACK、超时、重试、心跳确认和 UI 可视化。
- 设备运行时自动统计用电量和电费，LVGL 可查看分设备、分楼层、全屋总电费。
- 二楼客厅灯和主卧灯升级为 WS2812B 氛围灯，形成欢迎回家、观影、阅读、睡眠、雨天、警告等可展示场景。
- 安全场景作为作品主线：火灾、水浸/雨天、设备离线、求助按钮、离家布防。
- 所有演示动作都要有日志、状态、图表和兜底脚本，现场网络异常也能继续展示。

## 1、当前项目体检结论

### 1.1 已经具备的优势

当前仓库 `E:\MCU\esp32\p4\xiaozhi-for-p4` 已经不是从零开始，已有基础很强：

- 主控目标为 `CONFIG_IDF_TARGET_ESP32P4=y`，板型为 `CONFIG_BOARD_TYPE_ESP_P4_FUNCTION_EV_BOARD=y`。
- 主机已有小智语音聊天、音频任务、LVGL 显示、触摸、SD 卡、摄像头初始化框架。
- `main/smart_home` 已接入 LVGL 智能家居 UI、MQTT 服务、设备模型、MCP 工具、告警桥接。
- `slave` 下已有一楼、二楼、三楼从机工程。
- `shared/mqtt_iot_protocol.h` 已有 V2 心跳、广播、传感器上报、楼层设备 ID。
- 三楼已有烟雾、雨滴、求助按键采样任务，能触发火灾状态和小智告警。
- 主机 `SmartHomeMcp_RegisterTools()` 已提供 `self.iot.get_status`、`self.iot.get_sensors`、`self.iot.set_light`、`self.iot.set_relay`、`self.iot.set_servo_by_index` 等工具。
- `tools/mqtt_iot_simulator.py` 已有模拟器基础，可扩展为比赛现场兜底工具。

### 1.2 当前阻碍国一的短板

必须优先解决的不是“功能数量”，而是以下工程短板：

- MQTT 仍是 8 字节命令包，缺少 `seq`、事务表、执行结果码、超时回滚和错误可视化。
- UI 控制目前容易变成“发送即成功”的乐观模式，无法证明从机真实执行。
- MQTT 发布控制命令 QoS 仍偏弱，控制类命令应使用 QoS 1。
- 三个从机大量复制代码，协议或 bug 修改容易漏掉某一层。
- 网络状态只显示粗略连接结果，ESP-Hosted/Wi-Fi/MQTT 失败时现场排错成本高。
- 传感器阈值写死在头文件，缺少现场标定、NVS 保存、迟滞和误报控制。
- LVGL 页面已有雏形，但还缺少趋势图、事件时间线、事务状态、系统健康页和演示模式。
- 小智/MCP 控制返回值过于简单，不利于大模型解释“控制是否真正成功”。
- 现场演示材料、测试报告、故障预案还需要系统化。

## 2、国一评分导向拆解

### 2.1 评委真正想看到什么

| 维度 | 普通项目 | 国一项目 |
|---|---|---|
| 功能 | 能开灯、能显示数据 | 有完整 AIoT 场景闭环 |
| 稳定性 | 现场能跑一次 | 多次冷启动、断网恢复、长稳运行有数据 |
| 交互 | 按钮和页面 | 触控、语音、规则、告警统一入口 |
| 数据 | 显示模拟值 | 真实传感、滤波、阈值、趋势、日志 |
| 架构 | 代码能跑 | 主机、从机、协议、模型、UI 分层清楚 |
| 创新 | 接了大模型 | 大模型能调用工具、解释状态、参与决策 |
| 答辩 | 讲功能 | 讲链路、指标、风险、优化和工程验证 |

### 2.2 本项目推荐核心卖点

- **多节点协同**：P4 主机 + 三个 S3 楼层从机，具备真实分布式控制架构。
- **多模态交互**：LVGL 触控、小智语音、LLM/MCP、自动规则共用一套模型。
- **可靠控制闭环**：命令 `seq`、ACK、心跳确认、超时重试、UI pending 状态。
- **能耗费用可视化**：设备开启即累计运行时长、耗电量和电费，全屋节能收益可量化。
- **双氛围灯场景化展示**：二楼客厅和主卧各自支持独立自动模式、独立场景和安全联动，视觉展示更容易被评委感知。
- **安全场景主线**：火灾告警、雨天收衣、求助按钮、设备离线检测。
- **答辩级可视化**：总览大屏、网络诊断、趋势图、事件时间线、系统健康分。
- **可复现实验**：模拟器、压测脚本、日志导出、测试报告、演示兜底模式。

## 3、总体架构目标

### 3.1 主机五层架构

```text
Application / Xiaozhi
  小智状态机、语音唤醒、LLM、MCP 工具、语音播报

Smart Home Service
  MQTT 客户端、命令事务、规则引擎、告警中心、演示数据源

Device Model
  设备状态、传感器状态、楼层状态、系统状态、事务状态

LVGL HMI
  总览页、控制页、网络页、设置页、演示页、告警弹窗、趋势图

Board / BSP
  ESP-Hosted、Wi-Fi、音频、屏幕、触摸、TF 卡、按键、摄像头
```

### 3.2 关键分层约束

- LVGL 只能读模型和发送 UI 事件，不直接拼 MQTT topic。
- MQTT 回调只能更新模型或投递事件，不直接操作 LVGL 控件。
- MCP/LLM 只能调用 Smart Home Service，不直接改设备模型。
- 告警中心统一处理火灾、雨天、求助、离线、网络恢复等事件。
- 从机只负责采集、执行、ACK、心跳，不承担复杂 UI 或云端逻辑。

### 3.3 数据流闭环

```text
触控 / 小智语音 / LLM / 自动规则
  -> SmartHomeService_SendCommand()
  -> 生成 seq + 事务 pending
  -> MQTT publish QoS1
  -> 从机解析命令并执行外设
  -> 从机发布 ACK(seq, result_code)
  -> 从机立即补发 heartbeat
  -> 主机匹配 ACK，等待 heartbeat 确认状态
  -> Device Model 更新
  -> LVGL / MCP / 小智播报同步展示
  -> SD 卡记录事件日志
```

## 4、P0 迭代：可靠闭环

### 4.1 MQTT V3 协议升级

在 `shared/mqtt_iot_protocol.h` 中新增 V3 结构，保留 V2 兼容解析。

建议命令包：

```c
typedef struct {
    uint8_t magic;          // 0xA5
    uint8_t version;        // 3
    uint16_t seq;           // 主机生成，回绕允许
    uint8_t command;
    uint8_t device_id;
    uint8_t gpio_index;
    uint8_t value;
    uint8_t source;         // UI / MCP / RULE / DEMO
    uint32_t timestamp_ms;
    uint8_t reserved[4];
    uint8_t crc8;
} __attribute__((packed)) iot_command_v3_packet_t;
```

建议 ACK 包：

```c
typedef struct {
    uint8_t magic;
    uint8_t version;
    uint16_t seq;
    uint8_t command;
    uint8_t device_id;
    uint8_t gpio_index;
    uint8_t applied_value;
    uint8_t result_code;    // 0=OK, 1=INVALID_CMD, 2=INVALID_INDEX, 3=HW_FAIL
    uint8_t error_code;
    uint32_t timestamp_ms;
    uint8_t crc8;
} __attribute__((packed)) iot_ack_v3_packet_t;
```

### 4.2 主机事务表

新增 `smart_home/services/smart_home_transaction.*`：

- `SmartHomeTransaction_Begin()`：生成 seq，记录命令、目标、开始时间。
- `SmartHomeTransaction_OnAck()`：匹配 ACK，更新为 `acked` 或 `failed`。
- `SmartHomeTransaction_OnHeartbeat()`：用权威状态确认设备最终值。
- `SmartHomeTransaction_PollTimeout()`：超时标记失败，并通知 UI。
- `SmartHomeTransaction_GetSnapshot()`：供 LVGL 和 MCP 查询。

事务状态：

```text
IDLE -> PENDING -> ACKED -> CONFIRMED
                 -> FAILED
                 -> TIMEOUT
```

验收标准：

- 控制命令 100 次，UI 能正确显示 pending、成功、失败、超时。
- ACK 丢包时，UI 不显示成功，最终根据心跳或超时处理。
- 从机离线时，命令不会静默失败，MCP 返回明确错误。

### 4.3 MQTT QoS 策略

| Topic | QoS | retained | 说明 |
|---|---:|---:|---|
| `xiaozhi/iot/cmd/{floor}` | 1 | 否 | 控制命令，必须可靠送达 |
| `xiaozhi/iot/resp/{mac}` | 1 | 否 | ACK，必须可靠送达 |
| `xiaozhi/iot/alarm/{floor}` | 1 | 可选 | 告警事件 |
| `xiaozhi/iot/heartbeat/{mac}` | 0 | 否 | 高频状态，不需要积压 |
| `xiaozhi/iot/sensor/{mac}` | 0 | 否 | 普通传感数据 |
| `xiaozhi/iot/announce/{mac}` | 1 | 是 | 设备发现和在线声明 |

## 5、P0 迭代：网络稳定与现场兜底

### 5.1 网络状态机

新增 `smart_home/services/network_diag.*`，状态：

```text
BOOT
HOST_WAIT
WIFI_CONNECTING
WIFI_READY
MQTT_CONNECTING
MQTT_READY
DEGRADED
OFFLINE_DEMO
```

LVGL 网络页必须显示：

- 当前状态机阶段。
- Wi-Fi SSID、IP、RSSI。
- MQTT broker、连接状态、重连次数。
- 最近错误码和错误时间。
- 最近 MQTT 收包时间。
- 手动重连按钮。
- 进入离线演示按钮。

### 5.2 ESP-Hosted 风险处理

若出现类似 `Not able to connect with ESP-Hosted slave device`：

- 网络状态进入 `HOST_WAIT` 或 `DEGRADED`。
- 每次失败记录错误码和次数。
- 重试采用指数退避：1s、2s、4s、8s、16s、30s、60s。
- UI 不阻塞，小智聊天页和本地演示页仍可进入。
- 模拟数据源自动接管智能家居页面，标注“离线演示”。

验收标准：

- 冷启动 20 次，网络成功率目标 >= 95%。
- 热点断开后恢复，60 秒内 MQTT 自动恢复。
- 网络彻底不可用时，演示模式仍可完整展示 UI 和规则链路。

## 6、P0 迭代：真实传感与告警中心

### 6.1 统一传感器模型

每个传感器都应有：

```c
typedef struct {
    uint8_t floor_id;
    uint8_t sensor_type;
    uint16_t raw_mv;
    uint16_t filtered_mv;
    uint16_t threshold_warn;
    uint16_t threshold_alarm;
    uint8_t level;          // 0 normal, 1 warning, 2 alarm, 3 fault
    uint32_t updated_ms;
    bool valid;
} smart_home_sensor_t;
```

### 6.2 阈值与滤波

- 烟雾、雨滴、火焰至少使用滑动平均或中值滤波。
- 告警使用连续 N 次触发，恢复使用迟滞阈值。
- 阈值存入 NVS，设置页支持调节和恢复默认。
- 心跳必须同时上报原始值、滤波值和等级。

### 6.3 告警中心事件

新增 `smart_home_event_center`，统一事件：

- `DEVICE_ONLINE`
- `DEVICE_OFFLINE`
- `COMMAND_ACK`
- `COMMAND_TIMEOUT`
- `SENSOR_WARNING`
- `FIRE_ALARM`
- `RAIN_ALARM`
- `HELP_ALARM`
- `RULE_TRIGGERED`
- `NETWORK_RECOVERED`

告警链路：

```text
从机传感器状态
  -> MQTT heartbeat/alarm
  -> Device Model
  -> Event Center
  -> LVGL 弹窗 + 小智播报 + 自动联动 + SD 日志
```

验收标准：

- 火灾、雨天、求助、离线都能触发事件、显示、播报、记录。
- 告警解除不伪造传感器恢复，必须由传感器状态恢复驱动。
- 事件时间线能展示最近 20 条关键事件。

## 7、P1 迭代：从机 common 化

当前三份从机代码重复度高，建议重构为：

```text
slave/
├── slave_common/
│   ├── app_mqtt.c/.h
│   ├── app_protocol.c/.h
│   ├── app_heartbeat.c/.h
│   ├── app_control.c/.h
│   ├── app_sensor.c/.h
│   └── app_config.h
├── xiaozhi_slave_Firstfloor/
│   └── main/floor_config.h
├── xiaozhi_slave_Secondfloor/
│   └── main/floor_config.h
└── xiaozhi_slave_Thirdfloor/
    └── main/floor_config.h
```

每层只保留差异：

- 楼层 ID。
- 设备名称。
- GPIO 映射。
- 传感器类型。
- 阈值默认值。
- 设备数量。

验收标准：

- 修改 MQTT 协议只改 common 一处。
- 三个从机仍能分别构建。
- 三个从机上报字段一致，主机不需要写楼层特殊逻辑。

## 8、P1 迭代：LVGL 答辩级 HMI

### 8.1 总览页

总览页要让评委 10 秒看懂系统：

- 三层楼卡片：在线、设备数、告警等级、最近心跳。
- 安全状态：火灾、水浸/雨天、求助、离线。
- 系统健康分：网络、MQTT、从机在线率、命令成功率。
- 最近事件时间线。
- 一键进入演示模式。

### 8.2 控制页

控制页必须展示事务状态：

- 按钮点击后显示 pending 动画。
- 成功后显示 ACK 和最终状态。
- 超时后显示重试按钮。
- 离线设备置灰并解释原因。

### 8.3 网络页

网络页是现场排错核心：

- ESP-Hosted 状态。
- Wi-Fi 状态。
- MQTT 状态。
- Broker 地址。
- 最近错误。
- 重连次数。
- 收包计数。
- 手动重连。
- 离线演示模式。

### 8.4 数据页

增加趋势和统计：

- 烟雾曲线。
- 雨滴曲线。
- 命令成功率。
- 心跳延迟。
- 事件数量。

### 8.5 设置页

设置页必须服务现场：

- 传感器阈值调节。
- 阈值保存到 NVS。
- 恢复默认阈值。
- BOOT/触摸唤醒测试。
- 日志导出。
- 清空演示数据。

## 9、P1 迭代：小智与 MCP 能力升级

### 9.1 MCP 工具返回结构化结果

当前工具返回 `true` 不够。建议统一返回：

```json
{
  "accepted": true,
  "seq": 123,
  "state": "pending",
  "message": "已发送到二楼控制器，等待从机确认",
  "target": {
    "floor": 2,
    "type": "light",
    "index": 1,
    "value": 1
  }
}
```

### 9.2 必备 MCP 工具

- `self.iot.get_status`
- `self.iot.get_sensors`
- `self.iot.get_events`
- `self.iot.get_transactions`
- `self.iot.set_light`
- `self.iot.set_relay`
- `self.iot.set_servo_by_index`
- `self.iot.run_scene`
- `self.iot.set_threshold`
- `self.iot.enter_demo_mode`

### 9.3 语音演示脚本

答辩现场固定准备：

- “小智，查看三楼安全状态。”
- “小智，打开二楼客厅灯。”
- “小智，为什么刚才触发火灾告警？”
- “小智，模拟下雨并自动收衣服。”
- “小智，关闭所有灯。”
- “小智，导出最近事件日志。”

## 10、P1 迭代：边缘智能创新点

建议选择稳定可落地的边缘智能，不要押宝复杂大模型本地运行。

### 10.1 本地规则引擎

规则示例：

- 烟雾告警：关闭继电器、打开窗、触发小智播报。
- 雨天：自动收衣服、关闭天窗。
- 夜间低光照：自动开走廊灯。
- 离家模式：关闭所有灯、开启门磁/人体检测。
- 从机离线：语音提醒并在 UI 标红。

### 10.2 轻量异常检测

对传感器做滑动窗口统计：

- 均值。
- 方差。
- 突变检测。
- 连续异常次数。
- 传感器故障判断。

这样答辩时可以讲“边缘侧主动判断异常，而不是只把数据上传”。

### 10.3 摄像头可选增强

如果硬件摄像头稳定，再加入：

- 火焰图像辅助判断。
- 人体存在辅助安防。
- 拍照上传给小智解释。

摄像头不作为 P0 主链路，避免现场不稳定拖垮系统。

## 11、P1 迭代：能耗统计与电费可视化

这个功能建议加入，而且很适合国一答辩。它能把“控制设备”升级成“家庭能源管理”，让评委看到系统不只是会开关灯，还能量化运行成本和节能效果。

### 11.1 两阶段实现路线

第一阶段使用“额定功率估算”：

- 每个可控设备配置额定功率，例如灯 8W、风扇 45W、舵机类设备按动作功耗或待机功耗估算。
- 设备从关闭变为开启时记录 `on_since_ms`。
- 设备从开启变为关闭时结算本次运行时长，累计 `runtime_sec`、`energy_wh` 和 `cost_cent`。
- 设备持续开启时，LVGL 每秒或每 5 秒刷新一次临时累计值。
- 电价默认 0.60 元/kWh，可在设置页修改并保存到 NVS。

第二阶段升级为“真实功率采样”：

- 对高功率设备增加 HLW8012、BL0937 或 PZEM 电能计量模块。
- 心跳包增加实时功率 `power_w`、电压 `voltage_v`、电流 `current_ma`、累计电量 `energy_wh`。
- 对没有计量模块的设备继续使用额定功率估算。
- UI 明确标注数据来源：`估算` 或 `实测`。

### 11.2 主机模型新增字段

每个设备增加能耗字段：

```c
typedef struct {
    uint16_t rated_power_w;
    uint16_t live_power_w;
    uint32_t runtime_sec;
    uint32_t today_runtime_sec;
    uint32_t energy_wh_x100;
    uint32_t today_energy_wh_x100;
    uint32_t cost_cent;
    uint32_t today_cost_cent;
    int64_t on_since_ms;
    bool metering_enabled;
    bool metering_measured;
} rc_energy_t;
```

建议在 `rc_device_t` 中嵌入 `rc_energy_t energy;`，避免设备状态和能耗状态分散。

### 11.3 LVGL 页面表现

总览页新增“今日电费”和“累计电费”卡片：

- 今日用电：`xx.xx kWh`
- 今日电费：`¥x.xx`
- 累计电费：`¥xx.xx`
- 当前实时功率：`xxx W`

控制页每个设备卡片新增小字：

- 开启时：`已运行 12分35秒 · ¥0.03`
- 关闭时：`今日 ¥0.08 · 累计 1.2h`
- 有真实计量模块时：`实测 42W`
- 无真实计量模块时：`估算 8W`

设置页新增“电价与功率配置”：

- 电价输入，单位 `元/kWh`。
- 每个设备额定功率配置。
- 清空今日电费。
- 清空全部累计电费。
- 导出电费 CSV。

### 11.4 小智与 MCP 能力

新增 MCP 工具：

- `self.energy.get_summary`：查询全屋总电量、总电费、今日电费、实时功率。
- `self.energy.get_devices`：查询每个设备电费排行。
- `self.energy.set_tariff`：设置电价。
- `self.energy.reset_today`：清空今日统计。
- `self.energy.export_report`：导出电费报表。

语音演示：

- “小智，今天用了多少电？”
- “小智，哪个设备最费电？”
- “小智，把电价设置成 6 毛一度。”
- “小智，导出今天的电费报告。”

### 11.5 验收标准

- 设备开启后 5 秒内，LVGL 能看到运行时间和电费增加。
- 设备关闭后，电费累计值不丢失。
- 重启后累计电费从 NVS 或 SD 卡恢复。
- 修改电价后，后续计费按新电价计算，历史费用不被错误重算。
- 全屋总电费等于所有设备电费之和，误差不超过 1 分钱。
- 模拟器能模拟设备开关并验证电费增长。

## 12、P2 迭代：数据记录与报告

### 11.1 SD 卡目录

```text
/sdcard/xiaozhi_home/
├── events.log
├── sensor_history.csv
├── transactions.csv
├── system_health.json
├── config.json
└── demo_replay.json
```

### 11.2 必备记录字段

事件日志：

```text
time_ms,event_type,floor,severity,message,seq,result
```

传感器历史：

```text
time_ms,floor,sensor,raw_mv,filtered_mv,level,threshold_warn,threshold_alarm
```

事务记录：

```text
time_ms,seq,source,floor,cmd,index,value,state,latency_ms,result_code
```

### 11.3 答辩测试报告指标

必须整理成表格：

- 冷启动成功率。
- Wi-Fi/MQTT 恢复时间。
- 命令闭环成功率。
- ACK 平均延迟。
- 心跳丢失检测时间。
- UI 连续点击稳定性。
- 6 小时运行 heap 最低值。
- 任务栈最小水位。
- 传感器误报次数。

## 13、八周完整迭代路线

### 第 1 周：协议和事务闭环

- 设计 V3 协议。
- 主机实现事务表。
- 从机实现 V3 ACK。
- UI 显示 pending/成功/失败。
- 模拟器支持 ACK 延迟和丢包。

验收：100 次命令控制，成功、失败、超时都能被正确识别。

### 第 2 周：网络诊断和离线兜底

- 实现网络状态机。
- 网络页展示 Hosted/Wi-Fi/MQTT 状态。
- MQTT 退避重连。
- 离线演示模式。

验收：断网、broker 停止、从机离线时系统不崩，UI 明确显示原因。

### 第 3 周：传感器真实化和阈值管理

- 统一传感器结构。
- 增加滤波、防抖、迟滞。
- 阈值保存 NVS。
- 设置页调节阈值。

验收：传感器原始值、滤波值、等级、阈值在 UI 可解释。

### 第 4 周：告警中心和自动化规则

- 实现事件中心。
- 火灾、雨天、求助、离线事件统一流转。
- 小智播报和 LVGL 弹窗统一由事件中心触发。
- 自动规则引擎上线。

验收：四类告警都能触发、联动、记录、解除。

### 第 5 周：从机 common 化

- 抽出 `slave_common`。
- 三个楼层只保留配置。
- 统一心跳、ACK、传感上报。

验收：三从机独立构建通过，协议修改只改 common。

### 第 6 周：UI 大屏和演示模式

- 总览页、网络页、控制页、数据页重构。
- 增加事件时间线和趋势图。
- 增加一键演示脚本入口。

验收：评委不看串口也能理解系统状态和链路。

### 第 7 周：压测和指标固化

- 冷启动 20 次。
- 控制命令 300 次。
- UI 连续点击 100 次。
- 6 小时长稳运行。
- 整理测试报告。

验收：形成可放入答辩 PPT 的真实测试数据。

### 第 8 周：材料冻结和答辩打磨

- 冻结固件版本。
- 准备演示视频。
- 准备答辩 PPT。
- 准备故障兜底脚本。
- 准备现场操作清单。

验收：按 3 分钟脚本演示 5 次，失败率为 0；断网也能完整演示离线模式。

## 14、现场演示设计

### 13.1 三分钟主线

1. 开机进入总览页，展示三层楼在线、MQTT 已连接、传感器正常。
2. 触控打开二楼客厅灯，UI 显示 pending，再显示 ACK 成功。
3. 语音让小智关闭所有灯，小智调用 MCP 工具，UI 同步变化。
4. 触发三楼烟雾/火灾，LVGL 弹窗、小智播报、自动联动。
5. 触发雨滴传感器，系统自动收衣服并写入事件时间线。
6. 断开一个从机，网络/总览页显示离线和最近心跳超时。
7. 展示测试报告和日志导出。

### 13.2 故障兜底

| 故障 | 兜底方案 |
|---|---|
| Wi-Fi 连不上 | 进入离线演示模式 |
| MQTT broker 不通 | 本地 broker 或模拟器接管 |
| 从机没电 | 模拟器模拟三层从机 |
| 传感器不触发 | 演示页手动注入事件 |
| 小智云端不稳定 | 使用 LVGL + MCP 本地状态演示 |
| 摄像头失败 | 跳过摄像头，不影响主线 |

## 15、硬件增强建议

### 14.1 优先补齐

- AHT20/SHT31/SHT40：温湿度。
- BH1750：光照。
- MQ-2/MQ-135：烟雾。
- 火焰传感器：与烟雾组合判断。
- 雨滴/水浸传感器：雨天收衣和漏水场景。
- 门磁：安防演示。
- PIR 或 LD2410：人体存在。

### 14.2 拉开差距

- SCD40/SCD41：CO2 健康环境。
- PMS5003/PMSA003：PM2.5。
- HLW8012/BL0937/PZEM：功耗统计。
- 摄像头：火焰/人体辅助判断。

## 16、最终提交材料清单

- 项目源码：主机 + 三从机 + shared protocol + simulator。
- 固件二进制：主机和三从机版本固定。
- README 国赛版：系统介绍、架构图、硬件图、协议图、运行步骤。
- 测试报告：稳定性、压测、长稳、网络恢复、命令闭环。
- 答辩 PPT：问题背景、方案、架构、创新、测试、演示。
- 演示视频：正常演示 + 故障兜底。
- 现场脚本：3 分钟版、5 分钟版、问答版。
- 硬件连接图：主机、从机、传感器、执行器。

## 17、最终验收指标

| 指标 | 目标 |
|---|---:|
| 冷启动网络成功率 | >= 95% |
| MQTT 控制闭环成功率 | >= 98% |
| ACK 平均延迟 | <= 500 ms，视网络环境可放宽 |
| 从机离线检测 | <= 60 s |
| Wi-Fi/MQTT 恢复 | <= 60 s |
| UI 连续点击 | 100 次无崩溃 |
| 长稳运行 | 6 小时无重启 |
| heap 最低水位 | 有记录，不持续下降 |
| 传感器告警误报 | 可解释、可调阈值 |
| 离线演示模式 | 无网络可完整演示 |

## 18、最高优先级待办清单

- [ ] 升级 MQTT V3 协议，加入 `seq`、ACK 结果码和 CRC。
- [ ] 主机新增事务表，UI/MCP 都能查询命令状态。
- [ ] 控制命令改 QoS 1，ACK 改 QoS 1。
- [ ] 网络页展示 Hosted/Wi-Fi/MQTT 诊断信息。
- [ ] 增加离线演示模式和模拟器场景脚本。
- [ ] 传感器阈值迁移到 NVS，设置页可调。
- [ ] 实现统一告警中心和事件时间线。
- [ ] 新增能耗计费服务，设备开启后自动累计运行时长、电量和电费。
- [ ] LVGL 总览页和控制页展示今日电费、累计电费和实时功率估算。
- [ ] 从机抽出 `slave_common`。
- [ ] 补齐压测脚本和测试报告。
- [ ] 冻结现场演示脚本和答辩材料。

## 19、一句话结论

这个项目冲国一的正确路线是：==不要再横向堆功能，而要纵向打穿“感知、控制、ACK、状态、能耗、电费、告警、语音解释、日志证明、故障兜底”的完整闭环==。只要把 MQTT 事务可靠性、真实传感标定、能耗电费可视化、LVGL 答辩展示和现场兜底做好，它会比普通“ESP32 智能家居控制屏”高一个层级。
