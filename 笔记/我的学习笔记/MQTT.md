---
title: MQTT 协议学习笔记
tags: [MQTT, IoT, 物联网, ESP32, 协议]
created: 2026-05-04
---

# MQTT 协议学习笔记

## 一、MQTT 是什么

MQTT（Message Queuing Telemetry Transport）是一种**轻量级发布/订阅消息协议**，基于 TCP/IP，专为受限设备和低带宽网络设计。

### 1.1 核心特点

| 特点 | 说明 |
|------|------|
| 轻量 | 最小报文仅 **2 字节**（PINGREQ/PINGRESP） |
| 异步 | 发布者和订阅者不需要同时在线 |
| 一对多 | 一条消息可被多个订阅者接收 |
| QoS | 三种消息质量等级，灵活取舍 |
| 持久化 | 遗嘱消息 + 保留消息机制 |

### 1.2 应用场景

- IoT 设备间通信（传感器 → 网关 → 云平台）
- 智能家居控制
- 车联网、工业物联网
- 即时通讯（WhatsApp、Facebook Messenger 底层使用 MQTT）
- 小智项目：ESP32 主控与从设备通信

---

## 二、MQTT 架构

### 2.1 发布/订阅模型

```
              ┌──────────────┐
              │   Broker     │
              │  (消息代理)   │
              └──────┬───────┘
                     │
        ┌────────────┼────────────┐
        │            │            │
   ┌────▼────┐  ┌───▼────┐  ┌───▼────┐
   │Publisher│  │Subscri.│  │Subscri.│
   │ (发布)   │  │ (订阅)  │  │ (订阅)  │
   └─────────┘  └────────┘  └────────┘
```

- **Publisher（发布者）**：发送消息到某个主题
- **Subscriber（订阅者）**：接收某个主题的消息
- **Broker（代理）**：转发消息的中间服务器
- **Topic（主题）**：消息的分类路径
- 发布者和订阅者**互不知道对方的存在**，完全解耦

### 2.2 与小智项目的对应

```
┌────────────────────────────────────────────────┐
│                Mosquitto Broker                 │
│              (192.168.1.x:1883)                 │
└──────────┬──────────┬──────────┬───────────────┘
           │          │          │
    ┌──────▼──────┐ ┌─▼────────┐│
    │xiaozhi_master│ │一楼设备   ││
    │  (ESP32-S3) │ │(从设备)   ││
    │  发布+订阅   │ │ 订阅+发布 ││
    └─────────────┘ └─────────┘│
                              ┌─▼────────┐
                              │二楼设备   │
                              │(从设备)   │
                              │ 订阅+发布 │
                              └──────────┘
```

---

## 三、MQTT 报文格式

### 3.1 固定头部（Fixed Header）

```
Byte 1: [消息类型(4bit)] [标志位(4bit)]
Byte 2+: [剩余长度(可变长度编码)]
```

### 3.2 消息类型（15 种）

| 类型 | 值 | 方向 | 说明 |
|------|-----|------|------|
| **CONNECT** | 1 | C → S | 客户端连接请求 |
| **CONNACK** | 2 | S → C | 连接确认 |
| **PUBLISH** | 3 | 双向 | 发布消息 |
| **PUBACK** | 4 | 双向 | QoS 1 确认 |
| **PUBREC** | 5 | 双向 | QoS 2 第一步确认 |
| **PUBREL** | 6 | 双向 | QoS 2 第二步确认 |
| **PUBCOMP** | 7 | 双向 | QoS 2 完成确认 |
| **SUBSCRIBE** | 8 | C → S | 订阅请求 |
| **SUBACK** | 9 | S → C | 订阅确认 |
| **UNSUBSCRIBE** | 10 | C → S | 取消订阅 |
| **UNSUBACK** | 11 | S → C | 取消订阅确认 |
| **PINGREQ** | 12 | C → S | 心跳请求 |
| **PINGRESP** | 13 | S → C | 心跳响应 |
| **DISCONNECT** | 14 | C → S | 断开连接 |

### 3.3 可变长度编码

MQTT 用 1-4 字节表示剩余长度（最大 256MB）：

```
值 0-127：    1 字节   (0xxxxxxx)
值 128-16383：2 字节   (1xxxxxxx 0xxxxxxx)
值 16384-...：3-4 字节
```

每个字节最高位（bit 7）= 1 表示还有后续字节。

---

## 四、MQTT 连接流程

### 4.1 完整连接生命周期

```
客户端                            Broker
  │                                 │
  │── CONNECT ───────────────────→│
  │   Client ID: "xiaozhi_master"  │
  │   Clean Session: true          │
  │   Keep Alive: 240              │
  │   Username/Password (可选)      │
  │                                 │
  │←── CONNACK ──────────────────│
  │   Return Code: 0 (成功)        │
  │                                 │
  │── SUBSCRIBE ─────────────────→│
  │   Topic: "xiaozhi/iot/cmd/#"   │
  │   QoS: 0                       │
  │                                 │
  │←── SUBACK ───────────────────│
  │   Granted QoS: 0               │
  │                                 │
  │── PUBLISH ───────────────────→│
  │   Topic: "xiaozhi/iot/announce"│
  │   Payload: {"online": true}    │
  │                                 │
  │←── PUBLISH ──────────────────│  (收到其他设备消息)
  │   Topic: "xiaozhi/iot/cmd/1"   │
  │   Payload: {"cmd": 0x11}       │
  │                                 │
  │── PINGREQ ───────────────────→│  (Keep Alive 间隔)
  │←── PINGRESP ─────────────────│
  │                                 │
  │── DISCONNECT ────────────────→│
  │                                 │
```

### 4.2 CONNECT 报文参数

| 参数 | 说明 | 小智项目值 |
|------|------|----------|
| Client ID | 客户端唯一标识 | `"xiaozhi_master"` |
| Clean Session | 是否清除旧会话 | `true`（不持久化） |
| Keep Alive | 心跳间隔（秒） | `240` |
| Username | 认证用户名 | 无 |
| Password | 认证密码 | 无 |
| Will Topic | 遗嘱主题 | 可选 |
| Will Message | 遗嘱消息 | 可选 |

### 4.3 CONNACK 返回码

| 返回码 | 含义 | 处理方式 |
|--------|------|----------|
| 0 | 连接成功 | 正常继续 |
| 1 | 协议版本不支持 | 检查 MQTT 版本 |
| 2 | Client ID 被拒绝 | 更换 Client ID |
| 3 | Broker 不可用 | 重试连接 |
| 4 | 用户名/密码错误 | 检查认证信息 |
| 5 | 未授权 | 检查 ACL 权限 |

---

## 五、Topic 主题系统

### 5.1 主题格式

```
xiaozhi/iot/cmd/broadcast     ← 广播命令
xiaozhi/iot/cmd/1             ← 发送给设备 1
xiaozhi/iot/resp/abcdef123    ← 设备 abcdef123 的响应
xiaozhi/iot/heartbeat/1       ← 设备 1 的心跳
xiaozhi/iot/announce          ← 设备上线广播
```

### 5.2 通配符

| 通配符 | 含义 | 示例 |
|--------|------|------|
| `+` | 单层匹配 | `xiaozhi/iot/+/1` 匹配 `cmd/1`、`resp/1` |
| `#` | 多层匹配（只能在末尾） | `xiaozhi/iot/#` 匹配所有 IoT 主题 |

```
xiaozhi/iot/cmd/1      → 匹配 xiaozhi/iot/#         ✅
xiaozhi/iot/cmd/1      → 匹配 xiaozhi/iot/+/1       ✅
xiaozhi/iot/cmd/1      → 匹配 xiaozhi/iot/+         ❌ (多层)
xiaozhi/iot/cmd/b/1    → 匹配 xiaozhi/iot/+/1       ❌ (b 后面还有)
```

### 5.3 主题设计最佳实践

```
/{项目}/{类型}/{动作}/{设备ID}

小智项目：
/xiaozhi/iot/cmd/{device_id}      ← 命令
/xiaozhi/iot/resp/{device_id}     ← 响应
/xiaozhi/iot/heartbeat/{device_id}← 心跳
/xiaozhi/iot/announce/{device_id} ← 上线通知
```

---

## 六、QoS 服务质量等级

### 6.1 三个等级对比

| QoS | 名称 | 保证 | 报文数 | 适用场景 |
|-----|------|------|--------|----------|
| **0** | At Most Once | 最多一次，可能丢失 | 1 (PUBLISH) | 传感器周期数据、心跳 |
| **1** | At Least Once | 至少一次，可能重复 | 2 (PUBLISH + PUBACK) | 开关命令、配置 |
| **2** | Exactly Once | 恰好一次，不丢不重 | 4 (PUBLISH + PUBREC + PUBREL + PUBCOMP) | 关键操作（支付、安全） |

### 6.2 QoS 流程

```
QoS 0 (最多一次):
  发布者 ──PUBLISH──→ Broker ──PUBLISH──→ 订阅者
  (发完就不管了)

QoS 1 (至少一次):
  发布者 ──PUBLISH──→ Broker ──PUBLISH──→ 订阅者
  发布者 ←─PUBACK─── Broker ←─PUBACK─── 订阅者
  (没收到 PUBACK 就重发)

QoS 2 (恰好一次):
  发布者 ──PUBLISH──→ Broker ──PUBLISH──→ 订阅者
  发布者 ←─PUBREC─── Broker ←─PUBREC─── 订阅者
  发布者 ──PUBREL──→ Broker ──PUBREL──→ 订阅者
  发布者 ←─PUBCOMP─ Broker ←─PUBCOMP─ 订阅者
  (四次握手保证不重不漏)
```

### 6.3 小智项目 QoS 选择

```c
// 命令和响应：QoS 0（足够快速，丢了重发机制兜底）
// 心跳：QoS 0（周期发送，丢一条无所谓）
// 上线通知：QoS 1（确保被收到）
// 广播命令：QoS 0（实时性优先）
```

---

## 七、重要特性

### 7.1 保留消息（Retained Message）

```
发布者发送: PUBLISH(topic="sensor/temp", retained=true, payload=25.6)
            ↓
        Broker 保存这条消息
            ↓
新订阅者订阅 → 立即收到 25.6（即使发布者已经离线）
```

**用途**：存储设备最新状态，新设备加入时立即可知当前状态。

```c
// 小智项目中可用于：
// 设备上线时发布保留消息，其他设备立即知道它在线
PUBLISH("xiaozhi/iot/announce/1", retained=true, {"device":"一楼设备","online":true})
```

### 7.2 遗嘱消息（Last Will / LWT）

```
客户端连接时注册:
  Will Topic: "xiaozhi/iot/status/1"
  Will Message: {"online": false}
  Will QoS: 1
  Will Retained: true
```

- 客户端**异常断开**时，Broker 自动发布遗嘱消息
- 正常 DISCONNECT 不会发布
- 用于检测设备离线

```c
// ESP-IDF 配置示例
esp_mqtt_client_config_t mqtt_cfg = {
    .session.last_will.topic = "xiaozhi/iot/status/xiaozhi_master",
    .session.last_will.msg = "{\"online\":false}",
    .session.last_will.qos = 1,
    .session.last_will.retain = true,
};
```

### 7.3 Clean Session vs Persistent Session

| | Clean Session = true | Clean Session = false |
|------|------|------|
| 重连后 | 旧消息全部丢弃 | 保留订阅和未确认消息 |
| Broker 存储 | 不存储 | 存储（占用资源） |
| 适用场景 | 实时控制、不需要历史 | 需要消息不丢失 |
| 小智项目 | ✅ 推荐 | ❌ 不需要 |

---

## 八、MQTT v3.1.1 vs v5.0

| 特性 | v3.1.1 | v5.0 |
|------|--------|------|
| 发布年份 | 2014 | 2019 |
| 原因码 | 单字节返回码 | 详细原因码+字符串 |
| 共享订阅 | ❌ | ✅ `$share/group/topic` |
| 主题别名 | ❌ | ✅（减少带宽） |
| 消息过期 | ❌ | ✅（Message Expiry） |
| 请求/响应 | ❌ | ✅（Response Topic） |
| 用户属性 | ❌ | ✅（自定义 Key-Value） |
| ESP-IDF 支持 | ✅ 默认 | ✅ 需配置 |

**建议**：ESP32 用 v3.1.1 足够，v5.0 的新特性在嵌入式场景下用处不大。

---

## 九、ESP-IDF MQTT 客户端

### 9.1 基本配置

```c
#include "mqtt_client.h"

static esp_mqtt_client_handle_t mqtt_client = NULL;

void mqtt_app_start(void) {
    esp_mqtt_client_config_t mqtt_cfg = {
        .broker.address.uri = "mqtt://192.168.1.100:1883",
        .credentials.client_id = "xiaozhi_master",
        .session.keepalive = 240,
        .network.disable_auto_reconnect = false,
        .session.reconnect_timeout_ms = 60000,
    };

    mqtt_client = esp_mqtt_client_init(&mqtt_cfg);
    esp_mqtt_client_register_event(mqtt_client, ESP_EVENT_ANY_ID, mqtt_event_handler, NULL);
    esp_mqtt_client_start(mqtt_client);
}
```

### 9.2 事件处理

```c
static void mqtt_event_handler(void *handler_args, esp_event_base_t base,
                                int32_t event_id, void *event_data) {
    esp_mqtt_event_handle_t event = event_data;

    switch ((esp_mqtt_event_id_t)event_id) {
    case MQTT_EVENT_CONNECTED:
        ESP_LOGI(TAG, "MQTT 连接成功");
        // 订阅主题
        esp_mqtt_client_subscribe(mqtt_client, "xiaozhi/iot/cmd/#", 0);
        break;

    case MQTT_EVENT_DISCONNECTED:
        ESP_LOGW(TAG, "MQTT 断开连接");
        break;

    case MQTT_EVENT_DATA:
        ESP_LOGI(TAG, "收到消息: topic=%.*s, data=%.*s",
                 event->topic_len, event->topic,
                 event->data_len, event->data);
        // 处理收到的消息
        break;

    case MQTT_EVENT_PUBLISHED:
        ESP_LOGD(TAG, "消息发布成功, msg_id=%d", event->msg_id);
        break;

    case MQTT_EVENT_SUBSCRIBED:
        ESP_LOGD(TAG, "订阅成功, msg_id=%d", event->msg_id);
        break;

    case MQTT_EVENT_BEFORE_CONNECT:
        ESP_LOGI(TAG, "准备连接...");
        break;

    default:
        break;
    }
}
```

### 9.3 发布和订阅

```c
// 发布消息（QoS 0）
esp_mqtt_client_publish(mqtt_client,
    "xiaozhi/iot/resp/xiaozhi_master",
    "{\"status\":\"ok\"}", 0, 0, 0);

// 发布消息（QoS 1）
esp_mqtt_client_publish(mqtt_client,
    "xiaozhi/iot/announce/xiaozhi_master",
    "{\"device\":\"xiaozhi_master\",\"online\":true}", 0, 1, 1);

// 订阅主题
esp_mqtt_client_subscribe(mqtt_client, "xiaozhi/iot/cmd/#", 0);

// 取消订阅
esp_mqtt_client_unsubscribe(mqtt_client, "xiaozhi/iot/cmd/#");
```

---

## 十、Mosquitto Broker 管理

### 10.1 Docker 部署

```bash
# 启动
docker run -d --name mosquitto -p 1883:1883 -p 9001:9001 eclipse-mosquitto

# 带配置文件启动（推荐）
mkdir -p /mosquitto/config /mosquitto/data /mosquitto/log
# 创建配置文件后：
docker run -d --name mosquitto \
  -p 1883:1883 -p 9001:9001 \
  -v /mosquitto/config:/mosquitto/config \
  -v /mosquitto/data:/mosquitto/data \
  -v /mosquitto/log:/mosquitto/log \
  eclipse-mosquitto

# 停止 / 启动 / 删除
docker stop mosquitto
docker start mosquitto
docker rm mosquitto
```

### 10.2 mosquitto.conf 配置示例

```conf
# 监听端口
listener 1883
protocol mqtt

# WebSocket 端口
listener 9001
protocol websockets

# 允许匿名（开发用，生产环境应该关闭）
allow_anonymous true

# 持久化
persistence true
persistence_location /mosquitto/data/

# 日志
log_dest file /mosquitto/log/mosquitto.log
log_type all
```

### 10.3 命令行工具

```bash
# 订阅
mosquitto_sub -h 127.0.0.1 -p 1883 -t "xiaozhi/iot/#" -v

# 发布
mosquitto_pub -h 127.0.0.1 -p 1883 -t "xiaozhi/iot/cmd/broadcast" -m '{"cmd":0x30}'

# 带用户名密码
mosquitto_sub -h 127.0.0.1 -u admin -P password -t "topic"

# 保留消息
mosquitto_pub -h 127.0.0.1 -t "sensor/temp" -m "25.6" -r

# QoS 1
mosquitto_pub -h 127.0.0.1 -t "cmd/open" -m "1" -q 1

# 查看 Broker 状态
mosquitto_sub -h 127.0.0.1 -t '$SYS/broker/#' -v
```

---

## 十一、小智项目 MQTT 协议设计

### 11.1 主题规划

```
xiaozhi/iot/
├── cmd/                    ← 命令（主控 → 从设备）
│   ├── broadcast           ← 广播命令（所有设备）
│   ├── 1                   ← 发送给一楼设备
│   ├── 2                   ← 发送给二楼设备
│   └── 3                   ← 发送给三楼设备
├── resp/                   ← 响应（从设备 → 主控）
│   ├── {mac地址}           ← 按 MAC 地址区分
├── heartbeat/              ← 心跳
│   ├── 1                   ← 一楼设备心跳
│   ├── 2                   ← 二楼设备心跳
│   └── 3                   ← 三楼设备心跳
├── announce/               ← 上线通知
│   ├── {mac地址}           ← 按 MAC 地址区分
└── status/                 ← 状态（遗嘱消息主题）
```

### 11.2 命令格式

```c
// JSON 格式命令
{
    "cmd": 0x11,            // 命令类型
    "data": {               // 命令参数
        "gpio": 5,
        "level": 1
    }
}

// 命令类型定义
IOT_CMD_SET_GPIO = 0x01           // 设置 GPIO
IOT_CMD_GET_GPIO = 0x02           // 查询 GPIO
IOT_CMD_HEARTBEAT = 0x04          // 心跳
IOT_CMD_DISCOVER = 0x06           // 设备发现
IOT_CMD_ANNOUNCE_V2 = 0x08        // 上线通知 V2
IOT_CMD_SET_SERVO = 0x10          // 舵机控制
IOT_CMD_SET_LIGHT = 0x11          // 灯光控制
IOT_CMD_SET_RELAY = 0x12          // 继电器控制
IOT_CMD_BROADCAST_ALL_OFF = 0x30  // 全关
IOT_CMD_BROADCAST_ALL_ON = 0x31   // 全开
IOT_CMD_EMERGENCY = 0x34          // 紧急模式
```

### 11.3 设备发现流程

```
1. 从设备上电 → 连接 MQTT Broker
2. 从设备发布 ANNOUNCE_V2:
   Topic: xiaozhi/iot/announce/{mac}
   Payload: {"device_id":1, "name":"一楼设备", "gpios":[...]}

3. 主控收到 → 添加到设备列表
4. 主控定时检查心跳，超时标记离线
```

---

## 十二、调试技巧

### 12.1 串口日志分析

```
// 正常连接日志：
I mqtt_client: MQTT_EVENT_CONNECTED
I mqtt_client: MQTT_EVENT_SUBSCRIBED, msg_id=12345
I iot_ctrl: 设备发现: 一楼设备 (ID=1)

// 异常断开：
W mqtt_client: MQTT_EVENT_DISCONNECTED
E mqtt_client: MQTT publish failed

// 连接失败：
E mqtt_client: MQTT_EVENT_ERROR
E mqtt_client: esp_mqtt_client_publish message len=0
```

### 12.2 MQTTX 调试步骤

```
1. 连接到本地 Broker (127.0.0.1:1883)
2. 订阅 xiaozhi/iot/#
3. ESP32 上电 → 看到 ANNOUNCE 消息
4. 手动发布命令测试:
   Topic: xiaozhi/iot/cmd/broadcast
   Payload: {"cmd": 48}  ← 全关命令 (0x30)
5. 观察从设备响应消息
```

### 12.3 Wireshark 抓包

```
1. 选择 WiFi 网卡
2. 过滤: tcp.port == 1883
3. 右键 → Decode As → MQTT
4. 看到 CONNECT、PUBLISH、SUBSCRIBE 等报文
```

---

## 十三、常见问题

### Q: 消息丢了怎么办？

- 提高 QoS 等级（0→1→2）
- 应用层加确认机制（收到命令回复 ACK）
- 小智项目中：从设备收到命令后发布 resp 确认

### Q: 重复消息怎么处理？

- QoS 1 可能重复，需要应用层去重
- 给每条命令加唯一 ID（timestamp 或 UUID）
- 记录最近处理过的命令 ID

### Q: 多个设备用同一个 Client ID 会怎样？

- Broker 会踢掉前一个连接（"Client ID already in use"）
- 每个设备必须有唯一的 Client ID
- 小智项目：主控用 `xiaozhi_master`，从设备用 MAC 地址

### Q: Broker 挂了怎么办？

- ESP32 会自动重连（`reconnect_timeout_ms` 控制间隔）
- 生产环境用高可用 Broker（如 EMQX 集群）
- 开发阶段 Docker 容器挂了解决：`docker start mosquitto`

### Q: 消息太大发不出去？

- MQTT 默认最大消息 256KB（Mosquitto 默认 10MB）
- ESP-IDF 默认 `out_buffer_size` = 1024 字节
- 解决：增大 `mqtt_cfg.network.out_buffer_size`
