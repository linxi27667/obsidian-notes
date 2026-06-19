---
created: 2026-05-28 13:40
updated: 2026-05-28 14:55
tags: [智能家居, ESP32-P4, LVGL, MQTT, MCP, 国一冲刺, 编码计划]
project: xiaozhi-for-p4
repo: E:\MCU\esp32\p4\xiaozhi-for-p4
---

# ESP32-P4 小智智能家居国一完整迭代编码计划

> [!NOTE]
> 这份文档是给未来编码执行者使用的“落地施工图”。目标不是再讨论方向，而是按最优路径把当前项目从“能演示的智能家居”推进到“国一候选级 AIoT 系统”。  
> 本计划基于当前仓库真实结构编写：`main/smart_home`、`shared/mqtt_iot_protocol.h`、`slave/xiaozhi_slave_*`、`Mqtt` 包装类、`McpServer::AddTool()`、`ui_event_publish()`、`Settings`/NVS、LVGL v9 页面。

## 0、执行原则

### 0.1 最优路径排序

严格按下面顺序做：

1. **先做软件计时电费**：风险最低、展示效果强、不依赖新增硬件。
2. **再做二楼 WS2812B 氛围灯和自动模式体系**：增加强展示效果和场景化智能。
3. **再做 MQTT 事务闭环**：解决国一最关键的“可证明执行”。
4. **再做网络诊断和离线演示**：解决现场不可控风险。
5. **再做事件中心和告警闭环**：把火灾、雨天、求助、离线统一。
6. **再升级 LVGL 展示**：让评委不用看串口也能看懂。
7. **再升级 MCP/小智语义工具**：让 AI 入口变成作品亮点。
8. **最后做从机 common 化和测试报告**：降低维护成本，固化答辩证据。

### 0.2 禁止事项

- 不要在发送 MQTT 命令时就修改真实设备状态；必须等 ACK 或心跳确认。
- 不要在 MQTT 回调里直接操作 LVGL 控件；只能更新模型并 `ui_event_publish()`。
- 不要让低优先级功能抢音频任务；新增任务优先级不得超过 MQTT 任务。
- 不要每秒写 NVS；所有统计数据必须延迟保存或定期保存。
- 不要把“软件估算电费”包装成“真实电表计量”；UI 和答辩要标注“估算”。
- 不要先大重构从机；先把主机闭环做完，再抽 common。
- WS2812B 只允许由一个专用驱动层刷新，不允许普通 GPIO 刷新任务反复拉高/拉低数据脚。
- 自动模式必须有“全局开关”和“单设备覆盖开关”，全局开启不应强行覆盖被用户单独关闭自动模式的设备。
- 自动模式只能产生命令请求，不允许绕过 MQTT/ACK/模型闭环直接改 UI 状态。

### 0.3 当前可用真实 API

MQTT 包装类来自 `managed_components/78__esp-ml307/include/mqtt.h`：

```cpp
s_mqtt->SetKeepAlive(90);
s_mqtt->Connect(host, port, client_id, username, password);
s_mqtt->Disconnect();
s_mqtt->Publish(topic, payload, qos);
s_mqtt->Subscribe(topic, qos);
s_mqtt->OnConnected([]() {});
s_mqtt->OnDisconnected([]() {});
s_mqtt->OnError([](const std::string& error) {});
s_mqtt->OnMessage([](const std::string& topic, const std::string& payload) {});
s_mqtt->IsConnected();
s_mqtt->GetLastError();
```

UI 事件 API 来自 `main/smart_home/ui/core/ui_events.h`：

```c
ui_events_init();
ui_event_subscribe(UI_EVENT_MODEL_UPDATED, cb, user_data);
ui_event_unsubscribe(UI_EVENT_MODEL_UPDATED, cb, user_data);
ui_event_publish(UI_EVENT_MODEL_UPDATED);
ui_events_dispatch_pending();
```

MCP API 来自 `main/mcp_server.h`：

```cpp
auto& server = McpServer::GetInstance();
server.AddTool("tool.name", "description", PropertyList({...}),
    [](const PropertyList& properties) -> ReturnValue {
        return cJSON_CreateObject();
    });
```

NVS 可选两种方式：

```cpp
Settings settings("namespace", true);
int32_t value = settings.GetInt("key", default_value);
settings.SetInt("key", value);
```

或 C API：

```c
nvs_handle_t h;
nvs_open("namespace", NVS_READWRITE, &h);
nvs_get_i32(h, "key", &value);
nvs_set_i32(h, "key", value);
nvs_commit(h);
nvs_close(h);
```

本计划优先使用 C API，因为新增服务多数是 C 文件，能直接被现有 C UI 调用。

## 1、阶段一：软件计时电费系统

### 1.1 目标

实现“设备开启后开始按运行时间和额定功率估算电费”，LVGL 和 MCP 都能查看。

第一版只做软件计时计费，不接真实电能计量模块。

### 1.2 新增文件

新增：

```text
main/smart_home/services/energy_meter.h
main/smart_home/services/energy_meter.c
main/smart_home/services/energy_storage.h
main/smart_home/services/energy_storage.c
```

修改：

```text
main/CMakeLists.txt
main/smart_home/ui/model/mqtt_device_model.h
main/smart_home/ui/model/mqtt_device_model.c
main/smart_home/tasks/smart_home_tasks.cc
main/smart_home/ui/pages/page_data.c
main/smart_home/ui/pages/page_ctrl.c
main/smart_home/ui/pages/page_set.c
main/smart_home/mcp/smart_home_mcp_tool.cc
```

### 1.3 修改模型结构

文件：`main/smart_home/ui/model/mqtt_device_model.h`

在 `rc_device_t` 前新增：

```c
typedef enum {
    ENERGY_SOURCE_ESTIMATED = 0,
    ENERGY_SOURCE_MEASURED = 1,
} energy_source_t;

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
    energy_source_t source;
    bool enabled;
} rc_energy_t;
```

在 `rc_device_t` 末尾加入：

```c
rc_energy_t energy;
```

在 `mqtt_device_model_t` 末尾加入：

```c
uint16_t energy_tariff_cent_per_kwh;
uint32_t energy_total_wh_x100;
uint32_t energy_today_wh_x100;
uint32_t energy_total_cost_cent;
uint32_t energy_today_cost_cent;
uint16_t energy_live_power_w;
uint32_t energy_refresh_seq;
```

新增函数声明：

```c
void device_model_energy_recalculate_summary(void);
void device_model_energy_set_tariff(uint16_t cent_per_kwh);
uint16_t device_model_energy_get_tariff(void);
bool device_model_energy_set_rated_power(const char *device_id, uint16_t power_w);
void device_model_energy_mark_dirty(void);
rc_device_t *device_model_find_mutable_by_id(const char *id);
```

### 1.4 修改设备初始化

文件：`main/smart_home/ui/model/mqtt_device_model.c`

把 `add_device()` 签名从：

```c
static void add_device(rc_floor_t floor, rc_device_type_t type,
    const char *id, const char *name, bool controllable,
    uint8_t floor_id, uint8_t cmd_type, uint8_t gpio_index)
```

改为：

```c
static void add_device(rc_floor_t floor, rc_device_type_t type,
    const char *id, const char *name, bool controllable,
    uint8_t floor_id, uint8_t cmd_type, uint8_t gpio_index,
    uint16_t rated_power_w)
```

在函数末尾写入：

```c
d->energy.rated_power_w = rated_power_w;
d->energy.live_power_w = 0;
d->energy.runtime_sec = 0;
d->energy.today_runtime_sec = 0;
d->energy.energy_wh_x100 = 0;
d->energy.today_energy_wh_x100 = 0;
d->energy.cost_cent = 0;
d->energy.today_cost_cent = 0;
d->energy.on_since_ms = 0;
d->energy.source = ENERGY_SOURCE_ESTIMATED;
d->energy.enabled = rated_power_w > 0;
```

设备默认功率：

```c
add_device(... "floor1_gate", ..., 5);
add_device(... "floor1_hall_light", ..., 12);
add_device(... "floor2_master_light", ..., 10);     // 阶段二后改名为 floor2_master_ambient
add_device(... "floor2_living_light", ..., 12);     // 阶段二后改名为 floor2_living_ambient
add_device(... "floor2_toilet_light", ..., 8);
add_device(... "floor2_fan", ..., 45);
add_device(... "floor2_hanger", ..., 8);
add_device(... "floor3_balcony_light", ..., 10);
add_device(... "floor3_left_skylight", ..., 6);
add_device(... "floor3_right_skylight", ..., 6);
add_device(... "floor3_hanger", ..., 8);
```

新增可变查找函数：

```c
rc_device_t *device_model_find_mutable_by_id(const char *id)
{
    return find_device(id);
}
```

新增汇总函数：

```c
void device_model_energy_recalculate_summary(void)
{
    uint32_t total_wh = 0;
    uint32_t today_wh = 0;
    uint32_t total_cost = 0;
    uint32_t today_cost = 0;
    uint16_t live_power = 0;

    for (uint16_t i = 0; i < s_model.device_count; i++) {
        rc_device_t *d = &s_model.devices[i];
        total_wh += d->energy.energy_wh_x100;
        today_wh += d->energy.today_energy_wh_x100;
        total_cost += d->energy.cost_cent;
        today_cost += d->energy.today_cost_cent;
        if (d->power_on && d->connected && d->energy.enabled) {
            live_power += d->energy.rated_power_w;
        }
    }

    s_model.energy_total_wh_x100 = total_wh;
    s_model.energy_today_wh_x100 = today_wh;
    s_model.energy_total_cost_cent = total_cost;
    s_model.energy_today_cost_cent = today_cost;
    s_model.energy_live_power_w = live_power;
}
```

新增标记刷新：

```c
void device_model_energy_mark_dirty(void)
{
    s_model.energy_refresh_seq++;
    publish_update();
}
```

### 1.5 新增 `energy_meter.h`

文件：`main/smart_home/services/energy_meter.h`

写入：

```c
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "mqtt_device_model.h"

typedef struct {
    uint32_t total_wh_x100;
    uint32_t today_wh_x100;
    uint32_t total_cost_cent;
    uint32_t today_cost_cent;
    uint16_t live_power_w;
    uint16_t tariff_cent_per_kwh;
} energy_summary_t;

void energy_meter_init(void);
void energy_meter_on_device_power_changed(rc_device_t *device, bool old_on, bool new_on);
void energy_meter_tick(void);
void energy_meter_set_tariff(uint16_t cent_per_kwh);
uint16_t energy_meter_get_tariff(void);
bool energy_meter_set_device_rated_power(const char *device_id, uint16_t power_w);
void energy_meter_get_summary(energy_summary_t *out);
void energy_meter_reset_today(void);
void energy_meter_reset_all(void);
void energy_meter_format_money(uint32_t cent, char *buf, size_t buf_size);
void energy_meter_format_energy(uint32_t wh_x100, char *buf, size_t buf_size);
void energy_meter_format_runtime(uint32_t sec, char *buf, size_t buf_size);

#ifdef __cplusplus
}
#endif
```

### 1.6 新增 `energy_meter.c`

文件：`main/smart_home/services/energy_meter.c`

必须 include：

```c
#include "energy_meter.h"
#include "energy_storage.h"
#include "mqtt_device_model.h"
#include "ui_events.h"

#include <esp_log.h>
#include <esp_timer.h>
#include <stdio.h>
#include <string.h>
```

关键常量：

```c
static const char *TAG = "ENERGY";
static const uint16_t DEFAULT_TARIFF_CENT_PER_KWH = 60;
static int64_t s_last_save_ms = 0;
```

时间 API：

```c
static int64_t now_ms(void)
{
    return esp_timer_get_time() / 1000;
}
```

计算 API：

```c
static uint32_t calc_wh_x100(uint16_t power_w, uint32_t delta_sec)
{
    uint64_t v = (uint64_t)power_w * delta_sec * 100ULL;
    return (uint32_t)(v / 3600ULL);
}

static uint32_t calc_cost_cent(uint32_t wh_x100, uint16_t cent_per_kwh)
{
    uint64_t v = (uint64_t)wh_x100 * cent_per_kwh;
    return (uint32_t)(v / 100000ULL);
}
```

结算函数：

```c
static void settle_device_until_now(rc_device_t *device)
{
    if (!device || !device->energy.enabled || device->energy.on_since_ms <= 0) {
        return;
    }

    int64_t now = now_ms();
    if (now <= device->energy.on_since_ms) {
        return;
    }

    uint32_t delta_sec = (uint32_t)((now - device->energy.on_since_ms) / 1000);
    if (delta_sec == 0) {
        return;
    }

    uint16_t power_w = device->energy.rated_power_w;
    uint16_t tariff = device_model_energy_get_tariff();
    uint32_t wh = calc_wh_x100(power_w, delta_sec);
    uint32_t cost = calc_cost_cent(wh, tariff);

    device->energy.runtime_sec += delta_sec;
    device->energy.today_runtime_sec += delta_sec;
    device->energy.energy_wh_x100 += wh;
    device->energy.today_energy_wh_x100 += wh;
    device->energy.cost_cent += cost;
    device->energy.today_cost_cent += cost;
    device->energy.on_since_ms = now;
}
```

初始化：

```c
void energy_meter_init(void)
{
    if (device_model_energy_get_tariff() == 0) {
        device_model_energy_set_tariff(DEFAULT_TARIFF_CENT_PER_KWH);
    }
    energy_storage_load();
    device_model_energy_recalculate_summary();
    device_model_energy_mark_dirty();
    ESP_LOGI(TAG, "Energy meter initialized, tariff=%u cent/kWh",
             device_model_energy_get_tariff());
}
```

开关状态变化：

```c
void energy_meter_on_device_power_changed(rc_device_t *device, bool old_on, bool new_on)
{
    if (!device || !device->energy.enabled || old_on == new_on) {
        return;
    }

    if (new_on) {
        device->energy.on_since_ms = now_ms();
        device->energy.live_power_w = device->energy.rated_power_w;
    } else {
        settle_device_until_now(device);
        device->energy.on_since_ms = 0;
        device->energy.live_power_w = 0;
        energy_storage_schedule_save();
    }

    device_model_energy_recalculate_summary();
    device_model_energy_mark_dirty();
}
```

周期 tick：

```c
void energy_meter_tick(void)
{
    const mqtt_device_model_t *model = device_model_get();
    (void)model;

    for (uint16_t i = 0; i < device_model_count(); i++) {
        rc_device_t *d = device_model_find_mutable_by_id(device_model_at(i)->id);
        if (!d) continue;
        if (d->connected && d->power_on && d->energy.on_since_ms > 0) {
            settle_device_until_now(d);
        }
    }

    device_model_energy_recalculate_summary();
    device_model_energy_mark_dirty();

    int64_t now = now_ms();
    if (now - s_last_save_ms > 30000) {
        s_last_save_ms = now;
        energy_storage_schedule_save();
    }
}
```

注意：上面每秒结算会更新累计字段，但只 30 秒调度保存，不会每秒写 NVS。

格式化函数：

```c
void energy_meter_format_money(uint32_t cent, char *buf, size_t buf_size)
{
    snprintf(buf, buf_size, "¥%lu.%02lu",
             (unsigned long)(cent / 100),
             (unsigned long)(cent % 100));
}

void energy_meter_format_energy(uint32_t wh_x100, char *buf, size_t buf_size)
{
    uint32_t kwh_x1000 = wh_x100 / 100;
    snprintf(buf, buf_size, "%lu.%03lu kWh",
             (unsigned long)(kwh_x1000 / 1000),
             (unsigned long)(kwh_x1000 % 1000));
}

void energy_meter_format_runtime(uint32_t sec, char *buf, size_t buf_size)
{
    uint32_t h = sec / 3600;
    uint32_t m = (sec % 3600) / 60;
    uint32_t s = sec % 60;
    if (h > 0) snprintf(buf, buf_size, "%luh%02lum", (unsigned long)h, (unsigned long)m);
    else if (m > 0) snprintf(buf, buf_size, "%lum%02lus", (unsigned long)m, (unsigned long)s);
    else snprintf(buf, buf_size, "%lus", (unsigned long)s);
}
```

### 1.7 新增 `energy_storage.c`

文件：`main/smart_home/services/energy_storage.c`

使用 C NVS API：

```c
#include "energy_storage.h"
#include "mqtt_device_model.h"

#include <nvs.h>
#include <esp_log.h>
#include <string.h>
```

namespace：

```c
static const char *TAG = "ENERGY_STORE";
static const char *NS = "energy";
static bool s_save_pending;
```

设备 key 映射函数：

```c
static const char *device_key_prefix(const char *id)
{
    if (strcmp(id, "floor1_gate") == 0) return "f1g";
    if (strcmp(id, "floor1_hall_light") == 0) return "f1h";
    if (strcmp(id, "floor2_master_light") == 0) return "f2m";
    if (strcmp(id, "floor2_master_ambient") == 0) return "f2m";
    if (strcmp(id, "floor2_living_light") == 0) return "f2l";
    if (strcmp(id, "floor2_living_ambient") == 0) return "f2l";
    if (strcmp(id, "floor2_toilet_light") == 0) return "f2t";
    if (strcmp(id, "floor2_fan") == 0) return "f2f";
    if (strcmp(id, "floor2_hanger") == 0) return "f2r";
    if (strcmp(id, "floor3_balcony_light") == 0) return "f3b";
    if (strcmp(id, "floor3_left_skylight") == 0) return "f3ls";
    if (strcmp(id, "floor3_right_skylight") == 0) return "f3rs";
    if (strcmp(id, "floor3_hanger") == 0) return "f3r";
    return NULL;
}
```

读写 int helper：

```c
static void make_key(char *out, size_t out_size, const char *prefix, const char *suffix)
{
    snprintf(out, out_size, "%s_%s", prefix, suffix);
}

static uint32_t get_u32(nvs_handle_t h, const char *key, uint32_t def)
{
    uint32_t value = def;
    nvs_get_u32(h, key, &value);
    return value;
}

static void set_u32(nvs_handle_t h, const char *key, uint32_t value)
{
    ESP_ERROR_CHECK(nvs_set_u32(h, key, value));
}
```

load：

```c
bool energy_storage_load(void)
{
    nvs_handle_t h;
    esp_err_t err = nvs_open(NS, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "nvs_open failed: %s", esp_err_to_name(err));
        return false;
    }

    uint32_t tariff = get_u32(h, "tariff", 60);
    device_model_energy_set_tariff((uint16_t)tariff);

    for (uint16_t i = 0; i < device_model_count(); i++) {
        rc_device_t *d = device_model_find_mutable_by_id(device_model_at(i)->id);
        const char *prefix = device_key_prefix(d->id);
        if (!d || !prefix) continue;

        char key[16];
        make_key(key, sizeof(key), prefix, "pw");
        d->energy.rated_power_w = (uint16_t)get_u32(h, key, d->energy.rated_power_w);
        make_key(key, sizeof(key), prefix, "rt");
        d->energy.runtime_sec = get_u32(h, key, 0);
        make_key(key, sizeof(key), prefix, "trt");
        d->energy.today_runtime_sec = get_u32(h, key, 0);
        make_key(key, sizeof(key), prefix, "wh");
        d->energy.energy_wh_x100 = get_u32(h, key, 0);
        make_key(key, sizeof(key), prefix, "twh");
        d->energy.today_energy_wh_x100 = get_u32(h, key, 0);
        make_key(key, sizeof(key), prefix, "ct");
        d->energy.cost_cent = get_u32(h, key, 0);
        make_key(key, sizeof(key), prefix, "tct");
        d->energy.today_cost_cent = get_u32(h, key, 0);
    }

    nvs_close(h);
    return true;
}
```

save：

```c
bool energy_storage_save(void)
{
    nvs_handle_t h;
    esp_err_t err = nvs_open(NS, NVS_READWRITE, &h);
    if (err != ESP_OK) return false;

    set_u32(h, "tariff", device_model_energy_get_tariff());

    for (uint16_t i = 0; i < device_model_count(); i++) {
        const rc_device_t *src = device_model_at(i);
        const char *prefix = device_key_prefix(src->id);
        if (!prefix) continue;

        char key[16];
        make_key(key, sizeof(key), prefix, "pw");
        set_u32(h, key, src->energy.rated_power_w);
        make_key(key, sizeof(key), prefix, "rt");
        set_u32(h, key, src->energy.runtime_sec);
        make_key(key, sizeof(key), prefix, "trt");
        set_u32(h, key, src->energy.today_runtime_sec);
        make_key(key, sizeof(key), prefix, "wh");
        set_u32(h, key, src->energy.energy_wh_x100);
        make_key(key, sizeof(key), prefix, "twh");
        set_u32(h, key, src->energy.today_energy_wh_x100);
        make_key(key, sizeof(key), prefix, "ct");
        set_u32(h, key, src->energy.cost_cent);
        make_key(key, sizeof(key), prefix, "tct");
        set_u32(h, key, src->energy.today_cost_cent);
    }

    err = nvs_commit(h);
    nvs_close(h);
    s_save_pending = false;
    return err == ESP_OK;
}

void energy_storage_schedule_save(void)
{
    s_save_pending = true;
}
```

`energy_meter_tick()` 中如果发现 `s_save_pending` 无法访问，不要访问静态变量；改为在 `energy_storage_schedule_save()` 中只置位，在 `energy_meter_tick()` 每 30 秒直接调用 `energy_storage_save()`。

### 1.8 模型接入计费

文件：`mqtt_device_model.c`

新增 include：

```c
#include "../../services/energy_meter.h"
```

在 `device_model_apply_command_ack()` 内找到设备并更新状态处，改为：

```c
bool old_on = d->power_on;
d->connected = true;
d->power_on = value != 0;
d->value = value;
energy_meter_on_device_power_changed(d, old_on, d->power_on);
refresh_device_value(d);
changed = true;
```

在 `device_model_apply_heartbeat()` 内每个 known 设备更新处，改为：

```c
bool old_on = d->power_on;
d->connected = true;
d->power_on = value != 0;
d->value = value;
energy_meter_on_device_power_changed(d, old_on, d->power_on);
refresh_device_value(d);
```

在 `device_model_reset_runtime_data()` 里不要清空 `energy` 字段。

如果离线时要暂停计费，新增：

```c
void device_model_energy_pause_all_running(void)
{
    for (uint16_t i = 0; i < s_model.device_count; i++) {
        rc_device_t *d = &s_model.devices[i];
        if (d->energy.on_since_ms > 0) {
            energy_meter_on_device_power_changed(d, true, false);
            d->power_on = true;
        }
    }
}
```

然后在 MQTT 断开时调用，但不要把 `power_on` 改成 false。

### 1.9 任务接入

文件：`main/smart_home/tasks/smart_home_tasks.cc`

include：

```cpp
#include "../services/energy_meter.h"
```

新增句柄：

```cpp
static TaskHandle_t s_energy_task = nullptr;
```

新增任务：

```cpp
static void smart_home_energy_task(void* arg) {
    (void)arg;
    while (true) {
        energy_meter_tick();
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
```

在 `SmartHomeTasksStart()` 中，顺序改为：

```cpp
ui_events_init();
device_model_init();
energy_meter_init();
mqtt_client_init();
```

创建任务：

```cpp
BaseType_t energy_ret = xTaskCreatePinnedToCore(
    smart_home_energy_task,
    "sh_energy",
    4096,
    nullptr,
    2,
    &s_energy_task,
    1);

if (energy_ret != pdPASS) {
    s_energy_task = nullptr;
    ESP_LOGE(TAG, "Failed to create sh_energy task");
}
```

### 1.10 CMake 接入

文件：`main/CMakeLists.txt`

在 smart_home services 源文件处追加：

```cmake
"smart_home/services/energy_meter.c"
"smart_home/services/energy_storage.c"
```

在 `PRIV_REQUIRES` 确认已有或新增：

```cmake
nvs_flash
```

### 1.11 LVGL 总览页

文件：`main/smart_home/ui/pages/page_data.c`

include：

```c
#include "../../services/energy_meter.h"
```

在 `data_ctx_t` 新增：

```c
lv_obj_t *lbl_energy_today;
lv_obj_t *lbl_energy_today_cost;
lv_obj_t *lbl_energy_total_cost;
lv_obj_t *lbl_energy_live_power;
```

新增函数：

```c
static void energy_card(lv_obj_t *page, data_ctx_t *ctx)
{
    lv_obj_t *c = panel(page, 644, 342, 302, 96);
    icon_text(c, ICON_CHART, UI_COLOR_GREEN, 14, 14, 16);
    cn_label(c, tr("能耗电费", "Energy Cost"), 13, UI_COLOR_TEXT_STRONG, 40, 12, 120);

    cn_label(c, tr("今日用电", "Today"), 10, UI_COLOR_TEXT_SEC, 16, 38, 70);
    ctx->lbl_energy_today = cn_label(c, "0.000 kWh", 12, UI_COLOR_TEXT_STRONG, 86, 36, 80);

    cn_label(c, tr("今日电费", "Cost"), 10, UI_COLOR_TEXT_SEC, 168, 38, 70);
    ctx->lbl_energy_today_cost = cn_label(c, "¥0.00", 12, UI_COLOR_GREEN, 238, 36, 54);

    cn_label(c, tr("累计", "Total"), 10, UI_COLOR_TEXT_SEC, 16, 66, 50);
    ctx->lbl_energy_total_cost = cn_label(c, "¥0.00", 12, UI_COLOR_TEXT_STRONG, 66, 64, 80);

    cn_label(c, tr("功率", "Power"), 10, UI_COLOR_TEXT_SEC, 168, 66, 50);
    ctx->lbl_energy_live_power = cn_label(c, "0W", 12, UI_COLOR_ORANGE, 220, 64, 60);
}
```

新增更新函数：

```c
static void update_energy_card(data_ctx_t *ctx)
{
    if (!ctx) return;
    const mqtt_device_model_t *m = device_model_get();
    char buf[32];

    if (ctx->lbl_energy_today) {
        energy_meter_format_energy(m->energy_today_wh_x100, buf, sizeof(buf));
        lv_label_set_text(ctx->lbl_energy_today, buf);
    }
    if (ctx->lbl_energy_today_cost) {
        energy_meter_format_money(m->energy_today_cost_cent, buf, sizeof(buf));
        lv_label_set_text(ctx->lbl_energy_today_cost, buf);
    }
    if (ctx->lbl_energy_total_cost) {
        energy_meter_format_money(m->energy_total_cost_cent, buf, sizeof(buf));
        lv_label_set_text(ctx->lbl_energy_total_cost, buf);
    }
    if (ctx->lbl_energy_live_power) {
        lv_snprintf(buf, sizeof(buf), "%uW", (unsigned)m->energy_live_power_w);
        lv_label_set_text(ctx->lbl_energy_live_power, buf);
    }
}
```

在 `create_overview()` 里合适位置调用：

```c
energy_card(page, ctx);
```

在 `update_data()` 末尾调用：

```c
update_energy_card(ctx);
```

### 1.12 LVGL 控制页

文件：`main/smart_home/ui/pages/page_ctrl.c`

include：

```c
#include "../../services/energy_meter.h"
```

新增格式化：

```c
static void format_device_energy(const rc_device_t *d, char *buf, size_t buf_size)
{
    if (!d) {
        lv_snprintf(buf, buf_size, "");
        return;
    }
    if (!d->connected) {
        lv_snprintf(buf, buf_size, "%s", tr("离线·暂停计费", "Offline"));
        return;
    }
    if (d->power_on) {
        char runtime[16];
        char money[16];
        energy_meter_format_runtime(d->energy.today_runtime_sec, runtime, sizeof(runtime));
        energy_meter_format_money(d->energy.today_cost_cent, money, sizeof(money));
        lv_snprintf(buf, buf_size, "%s %s · %s", tr("运行", "Run"), runtime, money);
    } else {
        char money[16];
        energy_meter_format_money(d->energy.today_cost_cent, money, sizeof(money));
        lv_snprintf(buf, buf_size, "%s %s", tr("今日", "Today"), money);
    }
}
```

在 `device_button()` 底部替换最后状态文案：

```c
char energy_text[48];
format_device_energy(d, energy_text, sizeof(energy_text));
cn_label(btn, energy_text, 11,
    conn ? (on ? UI_COLOR_GREEN : UI_COLOR_TEXT_SEC) : UI_COLOR_TEXT_SEC,
    14, 90, 118);
```

修改 `state_hash()`，加入：

```c
const mqtt_device_model_t *m = device_model_get();
h ^= m->energy_refresh_seq;
h *= 16777619u;
```

### 1.13 LVGL 设置页

文件：`main/smart_home/ui/pages/page_set.c`

include：

```c
#include "../../services/energy_meter.h"
```

在 `set_ctx_t` 增加：

```c
lv_obj_t *energy_tariff_value;
```

新增设置行：

```c
ctx->energy_tariff_value = setting_row(list, y, ICON_CHART,
    tr("电价设置", "Tariff"), "¥0.60/kWh", UI_COLOR_TEXT_SEC,
    on_energy_tariff_row, ctx);
```

新增回调：

```c
static void on_energy_tariff_row(lv_event_t *e)
{
    set_ctx_t *ctx = (set_ctx_t *)lv_event_get_user_data(e);
    show_info_modal(ctx, tr("电价设置", "Tariff"),
        tr("第一版使用快捷电价：0.50、0.60、0.80 元/kWh。编码时在弹窗中放三个按钮，点击后调用 energy_meter_set_tariff(50/60/80)。",
           "Use quick tariff values in v1."));
}
```

如果要一步到位，写专用弹窗：

```c
static void set_tariff_and_close(set_ctx_t *ctx, uint16_t tariff)
{
    energy_meter_set_tariff(tariff);
    close_modal(ctx);
    UI_Manager_Rebuild_Current();
}
```

### 1.14 MCP 能耗工具

文件：`main/smart_home/mcp/smart_home_mcp_tool.cc`

include：

```cpp
#include "../services/energy_meter.h"
```

新增 summary JSON：

```cpp
static cJSON* build_energy_summary_json() {
    const mqtt_device_model_t* model = device_model_get();
    cJSON* root = cJSON_CreateObject();
    cJSON_AddNumberToObject(root, "tariff_cent_per_kwh", model->energy_tariff_cent_per_kwh);
    cJSON_AddNumberToObject(root, "today_wh_x100", model->energy_today_wh_x100);
    cJSON_AddNumberToObject(root, "today_cost_cent", model->energy_today_cost_cent);
    cJSON_AddNumberToObject(root, "total_wh_x100", model->energy_total_wh_x100);
    cJSON_AddNumberToObject(root, "total_cost_cent", model->energy_total_cost_cent);
    cJSON_AddNumberToObject(root, "live_power_w", model->energy_live_power_w);
    return root;
}
```

新增工具：

```cpp
server.AddTool("self.energy.get_summary",
    "Get estimated whole-home energy and electricity cost summary.",
    PropertyList(),
    [](const PropertyList& properties) -> ReturnValue {
        (void)properties;
        return build_energy_summary_json();
    });

server.AddTool("self.energy.set_tariff",
    "Set electricity tariff in cent per kWh.",
    PropertyList({
        Property("cent_per_kwh", kPropertyTypeInteger, 1, 300),
    }),
    [](const PropertyList& properties) -> ReturnValue {
        uint16_t tariff = static_cast<uint16_t>(properties["cent_per_kwh"].value<int>());
        energy_meter_set_tariff(tariff);
        return build_energy_summary_json();
    });

server.AddTool("self.energy.reset_today",
    "Reset today's estimated energy and cost counters.",
    PropertyList(),
    [](const PropertyList& properties) -> ReturnValue {
        (void)properties;
        energy_meter_reset_today();
        return build_energy_summary_json();
    });
```

## 2、阶段二：二楼 WS2812B 氛围灯和自动模式体系

### 2.1 目标

把二楼两个普通灯改成 WS2812B 氛围灯，并基于它们设计场景：

- 二楼主卧灯升级为“二楼主卧氛围灯”，用于睡眠、阅读、夜起柔光。
- 二楼客厅灯升级为“二楼客厅氛围灯”，用于欢迎回家、观影、雨天和警告提示。
- 支持颜色、亮度、灯效模式。
- 支持手动控制和自动模式。
- 支持全局自动模式：用户说“打开自动模式”时启用全屋自动规则。
- 支持单设备自动模式：用户可单独关闭某个器件的自动模式，例如“关闭主卧氛围灯自动模式”或“关闭客厅氛围灯自动模式”。
- LVGL 能显示每个设备的自动状态、当前场景、氛围灯颜色。

### 2.2 硬件约定

二楼从机当前普通灯：

```c
#define LIGHT_GPIO_1     GPIO_NUM_2
#define LIGHT_GPIO_2     GPIO_NUM_4
#define LIGHT_GPIO_3     GPIO_NUM_5
```

计划把 `LIGHT_GPIO_1` 和 `LIGHT_GPIO_2` 改为 WS2812B 数据脚：

```c
#define AMBIENT_BEDROOM_GPIO       GPIO_NUM_2
#define AMBIENT_LIVING_GPIO        GPIO_NUM_4
#define AMBIENT_BEDROOM_INDEX      0
#define AMBIENT_LIVING_INDEX       1
#define AMBIENT_WS2812_COUNT       8
```

约束：

- `LIGHT_GPIO_1` 和 `LIGHT_GPIO_2` 不再作为普通 GPIO 灯刷新。
- `LIGHT_GPIO_3` 保持普通厕所灯，GPIO5 不变。
- `g_device_flags.light[0]` 表示主卧氛围灯整体开关。
- `g_device_flags.light[1]` 表示客厅氛围灯整体开关。
- 颜色、亮度、场景模式使用新增命令控制。
- WS2812B 供电必须独立稳定，GND 必须和 ESP32-S3 共地。
- 第一版每路默认 8 颗灯珠，后续可通过宏调整。

### 2.3 协议新增命令

文件：`shared/mqtt_iot_protocol.h`

新增命令码：

```c
IOT_CMD_SET_AMBIENT_RGB      = 0x50,
IOT_CMD_SET_AMBIENT_SCENE    = 0x51,
IOT_CMD_SET_AUTO_MODE        = 0x52,
IOT_CMD_GET_AUTO_MODE        = 0x53,
```

新增自动模式目标：

```c
#define IOT_AUTO_TARGET_GLOBAL      0xFF
#define IOT_AUTO_TARGET_LIGHT_BASE  0x10
#define IOT_AUTO_TARGET_RELAY_BASE  0x20
#define IOT_AUTO_TARGET_SERVO_BASE  0x30
#define IOT_AUTO_TARGET_AMBIENT_BEDROOM  0x41
#define IOT_AUTO_TARGET_AMBIENT_LIVING   0x42
```

新增氛围灯场景：

```c
typedef enum {
    IOT_AMBIENT_SCENE_OFF = 0,
    IOT_AMBIENT_SCENE_WARM_HOME = 1,
    IOT_AMBIENT_SCENE_READING = 2,
    IOT_AMBIENT_SCENE_MOVIE = 3,
    IOT_AMBIENT_SCENE_SLEEP = 4,
    IOT_AMBIENT_SCENE_WARNING = 5,
    IOT_AMBIENT_SCENE_RAIN = 6,
    IOT_AMBIENT_SCENE_ENERGY_SAVE = 7,
    IOT_AMBIENT_SCENE_RAINBOW = 8,
} iot_ambient_scene_t;
```

第一版继续用 `iot_command_packet_t` 的 8 字节兼容包：

- `IOT_CMD_SET_AMBIENT_SCENE`
  - `device_id = 2`
  - `gpio_index = AMBIENT_BEDROOM_INDEX` 或 `AMBIENT_LIVING_INDEX`
  - `value = iot_ambient_scene_t`
- `IOT_CMD_SET_AUTO_MODE`
  - `device_id = 2` 或广播
  - `gpio_index = target`
  - `value = 0/1`

RGB 颜色需要 3 个通道，旧包不够。第一版有两种做法：

优先做法：先只支持预设场景，不做任意 RGB。

后续 V3 扩展做法：在 V3 包 `reserved[0..2]` 放 `r/g/b`，`value` 放亮度。

### 2.4 二楼从机新增 WS2812B 驱动

新增文件：

```text
slave/xiaozhi_slave_Secondfloor/main/APP/Inc/app_ambient_light.h
slave/xiaozhi_slave_Secondfloor/main/APP/Src/app_ambient_light.c
```

修改 CMake：

```cmake
"APP/Src/app_ambient_light.c"
```

并确认 `PRIV_REQUIRES` 包含：

```cmake
led_strip
```

如果当前 ESP-IDF 组件名不可用，则使用 `espressif__led_strip` 组件对应 include；优先尝试 `#include "led_strip.h"`。

头文件：

```c
#ifndef APP_AMBIENT_LIGHT_H
#define APP_AMBIENT_LIGHT_H

#include <stdint.h>
#include <stdbool.h>

typedef enum {
    AMBIENT_SCENE_OFF = 0,
    AMBIENT_SCENE_WARM_HOME = 1,
    AMBIENT_SCENE_READING = 2,
    AMBIENT_SCENE_MOVIE = 3,
    AMBIENT_SCENE_SLEEP = 4,
    AMBIENT_SCENE_WARNING = 5,
    AMBIENT_SCENE_RAIN = 6,
    AMBIENT_SCENE_ENERGY_SAVE = 7,
    AMBIENT_SCENE_RAINBOW = 8,
} ambient_scene_t;

void App_Ambient_Light_Init(void);
void App_Ambient_Light_Set_Power(uint8_t index, bool on);
void App_Ambient_Light_Set_Scene(uint8_t index, ambient_scene_t scene);
void App_Ambient_Light_Set_Brightness(uint8_t index, uint8_t brightness);
ambient_scene_t App_Ambient_Light_Get_Scene(uint8_t index);
bool App_Ambient_Light_Is_On(uint8_t index);
void App_Ambient_Light_Tick(void);

#endif
```

实现核心：

```c
#include "app_ambient_light.h"
#include "iot_control_task.h"
#include "mqtt_iot_protocol.h"

#include "led_strip.h"
#include "esp_log.h"
#include "driver/gpio.h"

#define AMBIENT_STRIP_COUNT     2
#define AMBIENT_WS2812_COUNT    8
#define AMBIENT_BEDROOM_GPIO    GPIO_NUM_2
#define AMBIENT_LIVING_GPIO     GPIO_NUM_4

typedef struct {
    led_strip_handle_t strip;
    gpio_num_t gpio;
    ambient_scene_t scene;
    uint8_t brightness;
    bool on;
} ambient_strip_t;

static ambient_strip_t s_strips[AMBIENT_STRIP_COUNT] = {
    { .strip = NULL, .gpio = AMBIENT_BEDROOM_GPIO, .scene = AMBIENT_SCENE_OFF, .brightness = 60, .on = false },
    { .strip = NULL, .gpio = AMBIENT_LIVING_GPIO, .scene = AMBIENT_SCENE_OFF, .brightness = 80, .on = false },
};
```

初始化：

```c
void App_Ambient_Light_Init(void)
{
    for (int i = 0; i < AMBIENT_STRIP_COUNT; i++) {
        led_strip_config_t strip_config = {
            .strip_gpio_num = s_strips[i].gpio,
            .max_leds = AMBIENT_WS2812_COUNT,
        };
        led_strip_rmt_config_t rmt_config = {
            .resolution_hz = 10 * 1000 * 1000,
            .flags.with_dma = false,
        };
        ESP_ERROR_CHECK(led_strip_new_rmt_device(&strip_config, &rmt_config, &s_strips[i].strip));
        led_strip_clear(s_strips[i].strip);
    }
}
```

颜色工具：

```c
static uint8_t scale(uint8_t brightness, uint8_t v)
{
    return (uint8_t)((uint16_t)v * brightness / 100);
}

static void fill_rgb(uint8_t index, uint8_t r, uint8_t g, uint8_t b)
{
    if (index >= AMBIENT_STRIP_COUNT || !s_strips[index].strip) return;
    for (int i = 0; i < AMBIENT_WS2812_COUNT; i++) {
        led_strip_set_pixel(s_strips[index].strip, i,
            scale(s_strips[index].brightness, r),
            scale(s_strips[index].brightness, g),
            scale(s_strips[index].brightness, b));
    }
    led_strip_refresh(s_strips[index].strip);
}
```

场景映射：

```c
static void apply_scene(uint8_t index)
{
    if (index >= AMBIENT_STRIP_COUNT || !s_strips[index].strip) return;
    ambient_strip_t *strip = &s_strips[index];
    if (!strip->on || strip->scene == AMBIENT_SCENE_OFF) {
        led_strip_clear(strip->strip);
        return;
    }

    switch (strip->scene) {
        case AMBIENT_SCENE_WARM_HOME: fill_rgb(index, 255, 150, 60); break;
        case AMBIENT_SCENE_READING: fill_rgb(index, 255, 220, 160); break;
        case AMBIENT_SCENE_MOVIE: fill_rgb(index, 60, 80, 255); break;
        case AMBIENT_SCENE_SLEEP: fill_rgb(index, 20, 30, 80); break;
        case AMBIENT_SCENE_WARNING: fill_rgb(index, 255, 0, 0); break;
        case AMBIENT_SCENE_RAIN: fill_rgb(index, 0, 120, 255); break;
        case AMBIENT_SCENE_ENERGY_SAVE: fill_rgb(index, 0, 180, 80); break;
        case AMBIENT_SCENE_RAINBOW:
            // 第一版可先固定紫色；后续在 Tick 中动态彩虹
            fill_rgb(index, 180, 60, 255);
            break;
        default: fill_rgb(index, 255, 150, 60); break;
    }
}
```

对外函数：

```c
void App_Ambient_Light_Set_Power(uint8_t index, bool on)
{
    if (index >= AMBIENT_STRIP_COUNT) return;
    s_strips[index].on = on;
    if (on && s_strips[index].scene == AMBIENT_SCENE_OFF) {
        s_strips[index].scene = index == 0 ? AMBIENT_SCENE_SLEEP : AMBIENT_SCENE_WARM_HOME;
    }
    apply_scene(index);
}

void App_Ambient_Light_Set_Scene(uint8_t index, ambient_scene_t scene)
{
    if (index >= AMBIENT_STRIP_COUNT) return;
    s_strips[index].scene = scene;
    s_strips[index].on = scene != AMBIENT_SCENE_OFF;
    apply_scene(index);
}
```

### 2.5 二楼控制任务改造

文件：`slave/xiaozhi_slave_Secondfloor/main/APP/Src/iot_control_task.c`

include：

```c
#include "app_ambient_light.h"
```

GPIO 数组中保留 `LIGHT_GPIO_1` 和 `LIGHT_GPIO_2` 也可以，但刷新普通 GPIO 时必须跳过 index 0 和 index 1。

初始化普通灯：

```c
for (int i = 0; i < LIGHT_COUNT; i++) {
    if (i == AMBIENT_BEDROOM_INDEX || i == AMBIENT_LIVING_INDEX) {
        continue;
    }
    HW_Gpio_Init(g_light_gpios[i]);
}
App_Ambient_Light_Init();
```

刷新普通灯：

```c
for (int i = 0; i < LIGHT_COUNT; i++) {
    if (i == AMBIENT_BEDROOM_INDEX || i == AMBIENT_LIVING_INDEX) {
        App_Ambient_Light_Set_Power(i, g_device_flags.light[i] == ON);
        continue;
    }
    HW_Gpio_Write(g_light_gpios[i], g_device_flags.light[i]);
}
App_Ambient_Light_Tick();
```

约束：

- `App_Ambient_Light_Set_Power()` 内部要避免每 100ms 重复刷新导致闪烁。实现时记录 `last_on` 和 `last_scene`，只有变化时刷新。
- `App_Ambient_Light_Tick()` 仅用于动态灯效，普通静态场景不刷新。

### 2.6 二楼 MQTT 命令处理

文件：`slave/xiaozhi_slave_Secondfloor/main/APP/Src/mqtt_receive.c`

include：

```c
#include "app_ambient_light.h"
```

在 `Process_Command()` 新增 case：

```c
case IOT_CMD_SET_AMBIENT_SCENE:
    if (cmd->gpio_index == AMBIENT_BEDROOM_INDEX || cmd->gpio_index == AMBIENT_LIVING_INDEX) {
        App_Ambient_Light_Set_Scene(cmd->gpio_index, (ambient_scene_t)cmd->value);
        g_device_flags.light[cmd->gpio_index] =
            (cmd->value == IOT_AMBIENT_SCENE_OFF) ? OFF : ON;
        Send_Response(cmd->command, cmd->gpio_index, cmd->value);
        MQTT_Heartbeat_Publish_Now();
    }
    break;
```

自动模式：

```c
case IOT_CMD_SET_AUTO_MODE:
    Auto_Mode_Set_Target(cmd->gpio_index, cmd->value != 0);
    Send_Response(cmd->command, cmd->gpio_index, cmd->value);
    MQTT_Heartbeat_Publish_Now();
    break;
```

`Auto_Mode_Set_Target()` 在后续自动模式服务中实现。

### 2.7 自动模式设计

自动模式分两层：

```text
全局自动模式 global_auto_enabled
每个硬件自动模式 device_auto_enabled[target]
```

有效自动状态：

```text
effective_auto = global_auto_enabled && device_auto_enabled[target]
```

语义：

- 用户说“打开自动模式”：`global_auto_enabled = true`。
- 用户说“关闭自动模式”：`global_auto_enabled = false`，所有自动规则停止。
- 用户说“关闭主卧氛围灯自动模式”：只把主卧氛围灯自动关闭。
- 用户说“关闭客厅氛围灯自动模式”：只把客厅氛围灯自动关闭。
- 用户说“打开客厅氛围灯自动模式”：只把客厅氛围灯自动允许，但如果全局自动是 false，则不会执行，UI 显示“单设备已允许，全局未开启”。
- 用户说“打开主卧氛围灯自动模式”：只把主卧氛围灯自动允许，但如果全局自动是 false，则不会执行，UI 显示“单设备已允许，全局未开启”。

新增主机服务：

```text
main/smart_home/services/auto_mode.h
main/smart_home/services/auto_mode.c
```

结构：

```c
typedef enum {
    AUTO_TARGET_FLOOR2_BEDROOM_AMBIENT = 0,
    AUTO_TARGET_FLOOR2_LIVING_AMBIENT,
    AUTO_TARGET_FLOOR2_FAN,
    AUTO_TARGET_FLOOR2_HANGER,
    AUTO_TARGET_FLOOR3_SKYLIGHT,
    AUTO_TARGET_FLOOR3_HANGER,
    AUTO_TARGET_MAX,
} auto_target_t;

typedef struct {
    bool global_enabled;
    bool target_enabled[AUTO_TARGET_MAX];
    uint32_t trigger_count[AUTO_TARGET_MAX];
    int64_t last_trigger_ms[AUTO_TARGET_MAX];
} auto_mode_state_t;
```

API：

```c
void auto_mode_init(void);
void auto_mode_set_global(bool enabled);
bool auto_mode_get_global(void);
void auto_mode_set_target(auto_target_t target, bool enabled);
bool auto_mode_get_target(auto_target_t target);
bool auto_mode_is_effective(auto_target_t target);
const auto_mode_state_t *auto_mode_get_state(void);
void auto_mode_on_event(const smart_home_event_t *event);
void auto_mode_tick(void);
```

持久化：

- namespace：`auto_mode`
- key：
  - `global`
  - `t0`、`t1`、`t2`...

### 2.8 自动场景规则

必须先实现以下 6 个稳定场景：

#### 场景 A：欢迎回家

触发：

- 全局自动开启。
- 二楼客厅氛围灯自动开启。
- 晚上 18:00 到 23:00，或用户语音“回家模式”。

动作：

```c
mqtt_send_command_v3(2, IOT_CMD_SET_AMBIENT_SCENE, 1,
    IOT_AMBIENT_SCENE_WARM_HOME, IOT_SOURCE_RULE);
mqtt_send_command_v3(2, IOT_CMD_SET_LIGHT, 0, 1, IOT_SOURCE_RULE);
```

效果：

- 二楼氛围灯暖黄色。
- 主卧氛围灯不自动跟随欢迎回家，避免夜间打扰。

#### 场景 B：观影模式

触发：

- 用户点击 LVGL 场景按钮或语音“打开观影模式”。

动作：

```c
mqtt_send_command_v3(2, IOT_CMD_SET_AMBIENT_SCENE, 1,
    IOT_AMBIENT_SCENE_MOVIE, IOT_SOURCE_MCP);
mqtt_send_command_v3(2, IOT_CMD_SET_LIGHT, 0, 0, IOT_SOURCE_MCP);
mqtt_send_command_v3(2, IOT_CMD_SET_LIGHT, 2, 0, IOT_SOURCE_MCP);
```

效果：

- 氛围灯蓝紫色。
- 普通灯关闭。

#### 场景 C：阅读模式

触发：

- 用户点击或语音“阅读模式”。

动作：

```c
mqtt_send_command_v3(2, IOT_CMD_SET_AMBIENT_SCENE, 0,
    IOT_AMBIENT_SCENE_READING, IOT_SOURCE_MCP);
```

效果：

- 主卧氛围灯暖白高亮。

#### 场景 D：睡眠模式

触发：

- 时间 23:00 后，或语音“睡眠模式”。

动作：

```c
mqtt_send_command_v3(2, IOT_CMD_SET_AMBIENT_SCENE, 0,
    IOT_AMBIENT_SCENE_SLEEP, IOT_SOURCE_RULE);
mqtt_send_command_v3(2, IOT_CMD_SET_AMBIENT_SCENE, 1,
    IOT_AMBIENT_SCENE_OFF, IOT_SOURCE_RULE);
mqtt_send_broadcast(IOT_CMD_BROADCAST_LIGHTS_OFF);
```

效果：

- 主卧氛围灯低亮深蓝，客厅氛围灯和其他普通灯关闭。

#### 场景 E：雨天收衣

触发：

- 二楼或三楼雨滴状态为 raining。
- 全局自动开启。
- 晾衣架自动模式开启。

动作：

```c
mqtt_send_command_v3(2, IOT_CMD_SET_SERVO, 6, 0, IOT_SOURCE_RULE);
mqtt_send_command_v3(3, IOT_CMD_SET_SERVO, 8, 0, IOT_SOURCE_RULE);
mqtt_send_command_v3(2, IOT_CMD_SET_AMBIENT_SCENE, 1,
    IOT_AMBIENT_SCENE_RAIN, IOT_SOURCE_RULE);
```

效果：

- 自动收二楼/三楼衣杆。
- 客厅氛围灯变雨天蓝色，主卧不联动。

#### 场景 F：火灾警告

触发：

- 火灾状态 >= 2。

动作：

```c
mqtt_send_command_v3(floor_id, IOT_CMD_BROADCAST_ALL_OFF, 0, 0, IOT_SOURCE_RULE);
mqtt_send_command_v3(2, IOT_CMD_SET_AMBIENT_SCENE, 1,
    IOT_AMBIENT_SCENE_WARNING, IOT_SOURCE_RULE);
mqtt_send_command_v3(2, IOT_CMD_SET_AMBIENT_SCENE, 0,
    IOT_AMBIENT_SCENE_WARNING, IOT_SOURCE_RULE);
```

效果：

- 主卧和客厅氛围灯均红色警告。
- 小智播报警告。
- LVGL 弹窗。

约束：

- 火灾警告优先级最高，即使该设备自动模式关闭，也允许进入安全警告灯效；这是安全兜底例外。
- 其他自动场景必须遵守单设备自动模式开关。

### 2.9 主机设备模型扩展

文件：`main/smart_home/ui/model/mqtt_device_model.h`

新增设备类型：

```c
RC_DEVICE_AMBIENT_LIGHT,
```

在 `rc_device_t` 新增：

```c
uint8_t ambient_scene;
uint8_t auto_enabled;
uint8_t auto_effective;
```

在 `device_model_type_name()`：

```c
case RC_DEVICE_AMBIENT_LIGHT: return "氛围灯";
```

在 `device_model_type_icon()`：

```c
case RC_DEVICE_AMBIENT_LIGHT: return ICON_LIGHTBULB;
```

在初始化中把二楼主卧灯、客厅灯从普通灯改为氛围灯：

```c
add_device(RC_FLOOR_2, RC_DEVICE_AMBIENT_LIGHT,
    "floor2_master_ambient", "主卧氛围灯",
    true, 2, IOT_CMD_SET_AMBIENT_SCENE, 0, 10);
add_device(RC_FLOOR_2, RC_DEVICE_AMBIENT_LIGHT,
    "floor2_living_ambient", "客厅氛围灯",
    true, 2, IOT_CMD_SET_AMBIENT_SCENE, 1, 12);
```

保留兼容：

- 如果 UI 或 MCP 仍按 `floor2_master_light` / `floor2_living_light` 查找，需要提供 alias。
- 建议不再新增旧普通灯设备，避免同一个硬件重复显示。

### 2.10 LVGL 自动模式页面设计

目前 UI 管理器只有 4 页：

```c
#define NAV_COUNT 4
总览 / 控制 / 网络 / 设置
```

第一版不新增第 5 页，避免改侧边栏布局。自动模式放到“设置页”和“总览页”：

总览页新增：

- 自动模式总开关状态卡片。
- 当前自动场景：欢迎回家/观影/阅读/睡眠/雨天/警告。

控制页设备卡片新增：

- 氛围灯卡片显示当前场景。
- 如果设备自动模式关闭，显示“自动关闭”。
- 如果全局自动关闭，显示“全局自动关”。

设置页新增“自动模式”区域：

```text
全局自动模式 [开/关]
客厅氛围灯自动 [开/关]
主卧氛围灯自动 [开/关]
二楼风扇自动 [开/关]
二楼晾衣架自动 [开/关]
三楼天窗自动 [开/关]
三楼晾衣架自动 [开/关]
```

LVGL 代码计划：

文件：`page_set.c`

新增 include：

```c
#include <stdint.h>
#include "../../services/auto_mode.h"
```

新增行：

```c
setting_row(panel, y, ICON_SETTINGS, tr("全局自动模式", "Global Auto"),
    auto_mode_get_global() ? tr("开启", "On") : tr("关闭", "Off"),
    auto_mode_get_global() ? UI_COLOR_GREEN : UI_COLOR_TEXT_SEC,
    on_auto_global_row, ctx);

setting_row(panel, y + 58, ICON_LIGHTBULB, tr("客厅氛围灯自动", "Living Ambient Auto"),
    auto_mode_target_text(AUTO_TARGET_FLOOR2_LIVING_AMBIENT),
    auto_mode_is_effective(AUTO_TARGET_FLOOR2_LIVING_AMBIENT) ? UI_COLOR_GREEN : UI_COLOR_TEXT_SEC,
    on_auto_target_row, (void *)AUTO_TARGET_FLOOR2_LIVING_AMBIENT);

setting_row(panel, y + 116, ICON_LIGHTBULB, tr("主卧氛围灯自动", "Bedroom Ambient Auto"),
    auto_mode_target_text(AUTO_TARGET_FLOOR2_BEDROOM_AMBIENT),
    auto_mode_is_effective(AUTO_TARGET_FLOOR2_BEDROOM_AMBIENT) ? UI_COLOR_GREEN : UI_COLOR_TEXT_SEC,
    on_auto_target_row, (void *)AUTO_TARGET_FLOOR2_BEDROOM_AMBIENT);
```

回调：

```c
static void on_auto_global_row(lv_event_t *e)
{
    bool next = !auto_mode_get_global();
    auto_mode_set_global(next);
    UI_Manager_Rebuild_Current();
}
```

单设备自动必须使用同一个回调，通过 `lv_event_get_user_data()` 区分目标设备，避免为每个设备复制一套逻辑：

```c
static const char *auto_mode_target_text(auto_target_t target)
{
    if (!auto_mode_get_global()) {
        return auto_mode_get_target(target) ? tr("已允许/全局关", "Allowed/Global Off") : tr("关闭", "Off");
    }
    return auto_mode_is_effective(target) ? tr("开启", "On") : tr("关闭", "Off");
}

static void on_auto_target_row(lv_event_t *e)
{
    auto_target_t target = (auto_target_t)(intptr_t)lv_event_get_user_data(e);
    bool next = !auto_mode_get_target(target);
    auto_mode_set_target(target, next);
    UI_Manager_Rebuild_Current();
}
```

### 2.11 LVGL 氛围灯场景控件

控制页中，对 `RC_DEVICE_AMBIENT_LIGHT` 使用专门卡片：

显示：

```text
主卧氛围灯 / 客厅氛围灯
场景：观影
自动：开启
今日 ¥0.03
[暖家] [阅读] [观影] [睡眠]
```

文件：`page_ctrl.c`

新增：

```c
static const char *ambient_scene_name(uint8_t scene)
{
    switch (scene) {
        case IOT_AMBIENT_SCENE_WARM_HOME: return tr("暖家", "Warm");
        case IOT_AMBIENT_SCENE_READING: return tr("阅读", "Read");
        case IOT_AMBIENT_SCENE_MOVIE: return tr("观影", "Movie");
        case IOT_AMBIENT_SCENE_SLEEP: return tr("睡眠", "Sleep");
        case IOT_AMBIENT_SCENE_WARNING: return tr("警告", "Warn");
        case IOT_AMBIENT_SCENE_RAIN: return tr("雨天", "Rain");
        case IOT_AMBIENT_SCENE_ENERGY_SAVE: return tr("节能", "Eco");
        default: return tr("关闭", "Off");
    }
}
```

场景按钮回调：

```c
static void on_ambient_scene_click(lv_event_t *e)
{
    ambient_scene_click_arg_t *arg = (ambient_scene_click_arg_t *)lv_event_get_user_data(e);
    mqtt_send_command_v3(2, IOT_CMD_SET_AMBIENT_SCENE, arg->index, arg->scene, IOT_SOURCE_UI);
}
```

约束：

- 场景按钮只发送命令，不直接修改 UI 状态。
- UI 等 ACK/心跳后显示新场景。
- 如果 MQTT 未连接，按钮应显示失败提示或进入 pending failed。

### 2.12 MCP 自动模式和场景工具

文件：`smart_home_mcp_tool.cc`

新增 include：

```cpp
#include "../services/auto_mode.h"
```

新增工具：

```cpp
server.AddTool("self.auto.set_global",
    "Enable or disable global smart-home automation mode.",
    PropertyList({ Property("enabled", kPropertyTypeBoolean) }),
    [](const PropertyList& properties) -> ReturnValue {
        bool enabled = properties["enabled"].value<bool>();
        auto_mode_set_global(enabled);
        cJSON* root = cJSON_CreateObject();
        cJSON_AddBoolToObject(root, "global_auto", enabled);
        return root;
    });
```

单设备自动：

```cpp
server.AddTool("self.auto.set_device",
    "Enable or disable automation for one device. target can be floor2_bedroom_ambient, floor2_living_ambient, floor2_fan, floor2_hanger, floor3_skylight, floor3_hanger.",
    PropertyList({
        Property("target", kPropertyTypeString),
        Property("enabled", kPropertyTypeBoolean),
    }),
    [](const PropertyList& properties) -> ReturnValue {
        std::string target = properties["target"].value<std::string>();
        bool enabled = properties["enabled"].value<bool>();
        auto_target_t t = target_from_string(target);
        auto_mode_set_target(t, enabled);
        cJSON* root = cJSON_CreateObject();
        cJSON_AddStringToObject(root, "target", target.c_str());
        cJSON_AddBoolToObject(root, "enabled", enabled);
        cJSON_AddBoolToObject(root, "effective", auto_mode_is_effective(t));
        return root;
    });
```

氛围灯场景：

```cpp
server.AddTool("self.scene.set_ambient",
    "Set floor-2 WS2812B ambient light scene. target can be bedroom or living.",
    PropertyList({
        Property("target", kPropertyTypeString, "living"),
        Property("scene", kPropertyTypeString),
    }),
    [](const PropertyList& properties) -> ReturnValue {
        std::string target = properties["target"].value<std::string>();
        std::string scene = properties["scene"].value<std::string>();
        uint8_t index = target == "bedroom" ? 0 : 1;
        uint8_t scene_id = ambient_scene_from_string(scene);
        uint16_t seq = mqtt_send_command_v3(2, IOT_CMD_SET_AMBIENT_SCENE, index, scene_id, IOT_SOURCE_MCP);
        cJSON* root = cJSON_CreateObject();
        cJSON_AddBoolToObject(root, "accepted", seq != 0);
        cJSON_AddNumberToObject(root, "seq", seq);
        cJSON_AddStringToObject(root, "target", target.c_str());
        cJSON_AddStringToObject(root, "scene", scene.c_str());
        return root;
    });
```

### 2.13 自动模式约束

必须写进实现注释和 README：

- 全局自动关闭时，所有普通自动规则不执行。
- 单设备自动关闭时，该设备不被普通自动规则控制。
- 火灾警告是安全例外，允许强制氛围灯红色警示。
- 手动控制优先级高于普通自动规则；用户手动设置后 60 秒内自动规则不覆盖该设备。
- 自动规则不能频繁触发同一设备；同一 target 最短触发间隔 10 秒。
- 自动模式状态必须持久化，重启后恢复。
- 自动模式动作必须通过 `mqtt_send_command_v3()` 发命令，不能直接改 `device_model`。

### 2.14 本阶段完成后成果

完成本阶段后，项目新增能力：

- 二楼主卧灯和客厅灯都升级为 WS2812B 彩色氛围灯。
- 主卧氛围灯支持阅读、睡眠、夜起柔光、警告场景。
- 客厅氛围灯支持暖家、观影、雨天、警告、节能、彩虹场景。
- LVGL 可分别切换主卧/客厅氛围灯场景。
- 小智可通过 MCP 分别设置主卧/客厅氛围灯场景。
- 支持全局自动模式。
- 支持每个硬件单独启停自动模式。
- 支持雨天自动收衣并切换蓝色雨天氛围。
- 支持火灾时强制红色警告氛围。
- 自动模式状态可视化，不再是隐藏逻辑。

## 3、阶段三：MQTT V3 事务闭环

### 3.1 目标

从“发送命令”升级为“命令有编号、有 ACK、有超时、有最终状态确认”。

### 3.2 修改协议

文件：`shared/mqtt_iot_protocol.h`

保留原 `iot_command_packet_t` 和 V2 心跳，新增加 V3，不删旧结构。

新增：

```c
#define IOT_PACKET_MAGIC 0xA5
#define IOT_PROTOCOL_VERSION_3 3
#define IOT_CMD_ACK_V3 0x40

typedef enum {
    IOT_SOURCE_UI = 1,
    IOT_SOURCE_MCP = 2,
    IOT_SOURCE_RULE = 3,
    IOT_SOURCE_DEMO = 4,
} iot_command_source_t;

typedef enum {
    IOT_RESULT_OK = 0,
    IOT_RESULT_INVALID_CMD = 1,
    IOT_RESULT_INVALID_INDEX = 2,
    IOT_RESULT_HW_FAIL = 3,
} iot_result_code_t;

typedef struct {
    uint8_t magic;
    uint8_t version;
    uint16_t seq;
    uint8_t command;
    uint8_t device_id;
    uint8_t gpio_index;
    uint8_t value;
    uint8_t source;
    uint32_t timestamp_ms;
    uint8_t reserved[4];
    uint8_t crc8;
} __attribute__((packed)) iot_command_v3_packet_t;

typedef struct {
    uint8_t magic;
    uint8_t version;
    uint16_t seq;
    uint8_t command;
    uint8_t device_id;
    uint8_t gpio_index;
    uint8_t applied_value;
    uint8_t result_code;
    uint8_t error_code;
    uint32_t timestamp_ms;
    uint8_t crc8;
} __attribute__((packed)) iot_ack_v3_packet_t;
```

新增 CRC helper：

```c
static inline uint8_t iot_crc8_xor(const uint8_t *data, size_t len)
{
    uint8_t crc = 0;
    for (size_t i = 0; i < len; i++) {
        crc ^= data[i];
    }
    return crc;
}
```

### 3.3 新增事务服务

新增文件：

```text
main/smart_home/services/smart_home_transaction.h
main/smart_home/services/smart_home_transaction.c
```

结构：

```c
typedef enum {
    SH_TX_IDLE = 0,
    SH_TX_PENDING,
    SH_TX_ACKED,
    SH_TX_CONFIRMED,
    SH_TX_FAILED,
    SH_TX_TIMEOUT,
} sh_transaction_state_t;

typedef struct {
    uint16_t seq;
    uint8_t floor_id;
    uint8_t cmd_type;
    uint8_t gpio_index;
    uint8_t value;
    uint8_t source;
    sh_transaction_state_t state;
    uint8_t result_code;
    int64_t started_ms;
    int64_t updated_ms;
} sh_transaction_t;
```

API：

```c
void sh_transaction_init(void);
uint16_t sh_transaction_begin(uint8_t floor_id, uint8_t cmd_type, uint8_t gpio_index, uint8_t value, uint8_t source);
void sh_transaction_on_ack(const iot_ack_v3_packet_t *ack);
void sh_transaction_on_confirmed(uint8_t floor_id, uint8_t cmd_type, uint8_t gpio_index, uint8_t value);
void sh_transaction_poll_timeout(void);
const sh_transaction_t *sh_transaction_find(uint16_t seq);
uint16_t sh_transaction_latest_seq(void);
```

内部数组：

```c
#define SH_TX_MAX 32
static sh_transaction_t s_tx[SH_TX_MAX];
static uint16_t s_next_seq = 1;
static portMUX_TYPE s_tx_lock = portMUX_INITIALIZER_UNLOCKED;
```

开始事务：

```c
uint16_t sh_transaction_begin(...)
{
    portENTER_CRITICAL(&s_tx_lock);
    uint16_t seq = s_next_seq++;
    if (s_next_seq == 0) s_next_seq = 1;
    sh_transaction_t *slot = &s_tx[seq % SH_TX_MAX];
    memset(slot, 0, sizeof(*slot));
    slot->seq = seq;
    slot->floor_id = floor_id;
    slot->cmd_type = cmd_type;
    slot->gpio_index = gpio_index;
    slot->value = value;
    slot->source = source;
    slot->state = SH_TX_PENDING;
    slot->started_ms = esp_timer_get_time() / 1000;
    slot->updated_ms = slot->started_ms;
    portEXIT_CRITICAL(&s_tx_lock);
    ui_event_publish(UI_EVENT_MODEL_UPDATED);
    return seq;
}
```

超时：

```c
if (tx->state == SH_TX_PENDING && now - tx->started_ms > 3000) {
    tx->state = SH_TX_TIMEOUT;
    tx->updated_ms = now;
}
```

### 3.4 改造主机 MQTT 发送

文件：`main/smart_home/services/xiaozhi_mqtt.h`

保留旧 API，新增：

```c
uint16_t mqtt_send_command_v3(uint8_t floor_id, uint8_t cmd_type, uint8_t gpio_index, uint8_t value, uint8_t source);
```

文件：`xiaozhi_mqtt.cc`

include：

```cpp
#include "smart_home_transaction.h"
```

新增构包：

```cpp
extern "C" uint16_t mqtt_send_command_v3(uint8_t floor_id, uint8_t cmd_type,
    uint8_t gpio_index, uint8_t value, uint8_t source)
{
    if (!mqtt_client_is_connected()) {
        ESP_LOGW(TAG, "Cannot send V3 command: MQTT not connected");
        return 0;
    }

    uint16_t seq = sh_transaction_begin(floor_id, cmd_type, gpio_index, value, source);

    iot_command_v3_packet_t pkt = {};
    pkt.magic = IOT_PACKET_MAGIC;
    pkt.version = IOT_PROTOCOL_VERSION_3;
    pkt.seq = seq;
    pkt.command = cmd_type;
    pkt.device_id = floor_id;
    pkt.gpio_index = gpio_index;
    pkt.value = value;
    pkt.source = source;
    pkt.timestamp_ms = (uint32_t)(esp_timer_get_time() / 1000);
    pkt.crc8 = iot_crc8_xor(reinterpret_cast<const uint8_t*>(&pkt), sizeof(pkt) - 1);

    char topic[48];
    snprintf(topic, sizeof(topic), "%s%u", MQTT_TOPIC_CMD_PREFIX, floor_id);
    std::string payload(reinterpret_cast<const char*>(&pkt), sizeof(pkt));
    bool ok = s_mqtt->Publish(topic, payload, 1);
    ESP_LOGI(TAG, "CMDv3 -> %s seq=%u ok=%d cmd=0x%02X gpio=%u val=%u",
             topic, seq, ok, cmd_type, gpio_index, value);
    return ok ? seq : 0;
}
```

旧 `mqtt_send_command()` 改为调用 V3：

```cpp
mqtt_send_command_v3(floor_id, cmd_type, gpio_index, value, IOT_SOURCE_UI);
```

### 3.5 解析 ACK

文件：`xiaozhi_mqtt.cc`

修改 `process_response()`：

```cpp
if (payload.size() >= sizeof(iot_ack_v3_packet_t)) {
    const auto* ack = reinterpret_cast<const iot_ack_v3_packet_t*>(payload.data());
    if (ack->magic == IOT_PACKET_MAGIC && ack->version == IOT_PROTOCOL_VERSION_3) {
        uint8_t crc = iot_crc8_xor(reinterpret_cast<const uint8_t*>(ack), sizeof(*ack) - 1);
        if (crc == ack->crc8) {
            sh_transaction_on_ack(ack);
            if (ack->result_code == IOT_RESULT_OK) {
                device_model_apply_command_ack(
                    ack->device_id, ack->command, ack->gpio_index, ack->applied_value);
            }
        }
        return;
    }
}
```

### 3.6 从机兼容 V3

文件：`slave/xiaozhi_slave_*/main/APP/Src/mqtt_receive.c`

在 `MQTT_EVENT_DATA` 里先判断 V3：

```c
if (event->data_len >= (int)sizeof(iot_command_v3_packet_t)) {
    const iot_command_v3_packet_t *cmd = (const iot_command_v3_packet_t *)event->data;
    if (cmd->magic == IOT_PACKET_MAGIC && cmd->version == IOT_PROTOCOL_VERSION_3) {
        Process_Command_V3(cmd);
        break;
    }
}
```

新增 ACK：

```c
static void Send_Ack_V3(const iot_command_v3_packet_t *cmd, uint8_t applied_value, uint8_t result)
{
    iot_ack_v3_packet_t ack = {};
    ack.magic = IOT_PACKET_MAGIC;
    ack.version = IOT_PROTOCOL_VERSION_3;
    ack.seq = cmd->seq;
    ack.command = cmd->command;
    ack.device_id = DEVICE_ID_NUM;
    ack.gpio_index = cmd->gpio_index;
    ack.applied_value = applied_value;
    ack.result_code = result;
    ack.error_code = 0;
    ack.timestamp_ms = (uint32_t)(xTaskGetTickCount() * portTICK_PERIOD_MS);
    ack.crc8 = iot_crc8_xor((const uint8_t *)&ack, sizeof(ack) - 1);

    char topic[64];
    snprintf(topic, sizeof(topic), MQTT_TOPIC_RESP_PREFIX "%s", s_mac_str);
    esp_mqtt_client_publish(s_mqtt_client, topic, (const char *)&ack, sizeof(ack), 1, 0);
}
```

V3 命令处理可以复用旧逻辑，但必须回 ACK。

## 4、阶段四：网络诊断和离线演示

### 4.1 新增网络诊断服务

新增：

```text
main/smart_home/services/network_diag.h
main/smart_home/services/network_diag.c
```

结构：

```c
typedef enum {
    NET_DIAG_BOOT = 0,
    NET_DIAG_HOST_WAIT,
    NET_DIAG_WIFI_READY,
    NET_DIAG_MQTT_CONNECTING,
    NET_DIAG_MQTT_READY,
    NET_DIAG_DEGRADED,
    NET_DIAG_OFFLINE_DEMO,
} network_diag_state_t;

typedef struct {
    network_diag_state_t state;
    uint32_t reconnect_count;
    int last_error;
    char last_error_text[64];
    int64_t last_error_ms;
    int64_t last_mqtt_rx_ms;
    bool offline_demo;
} network_diag_t;
```

API：

```c
void network_diag_init(void);
void network_diag_set_state(network_diag_state_t state);
void network_diag_set_error(int err, const char *text);
void network_diag_mark_mqtt_rx(void);
void network_diag_set_offline_demo(bool enabled);
const network_diag_t *network_diag_get(void);
```

### 4.2 接入 MQTT 服务

文件：`xiaozhi_mqtt.cc`

在 `mqtt_client_start()` 里：

```cpp
network_diag_set_state(NET_DIAG_MQTT_CONNECTING);
```

连接成功：

```cpp
network_diag_set_state(NET_DIAG_MQTT_READY);
```

错误：

```cpp
network_diag_set_error(s_mqtt ? s_mqtt->GetLastError() : -1, error.c_str());
network_diag_set_state(NET_DIAG_DEGRADED);
```

收到消息：

```cpp
network_diag_mark_mqtt_rx();
```

### 4.3 离线演示模式

新增：

```text
main/smart_home/services/demo_mode.h
main/smart_home/services/demo_mode.c
```

API：

```c
void demo_mode_set_enabled(bool enabled);
bool demo_mode_is_enabled(void);
void demo_mode_tick(void);
void demo_mode_trigger_fire(uint8_t floor_id);
void demo_mode_trigger_rain(uint8_t floor_id);
void demo_mode_set_controller_online(uint8_t floor_id, bool online);
```

`demo_mode_tick()` 每 1 秒模拟：

```c
device_model_set_controller_online(1, true);
device_model_set_controller_online(2, true);
device_model_set_controller_online(3, true);
```

模拟设备状态时，直接调用：

```c
device_model_apply_command_ack(floor, cmd, gpio, value);
```

### 4.4 网络页改造

文件：`main/smart_home/ui/pages/page_net.c`

展示：

- 网络诊断状态。
- MQTT 收包时间。
- 重连次数。
- 最近错误。
- 进入/退出离线演示按钮。

按钮回调：

```c
demo_mode_set_enabled(!demo_mode_is_enabled());
ui_event_publish(UI_EVENT_MODEL_UPDATED);
```

## 5、阶段五：事件中心和告警闭环

### 5.1 新增事件中心

新增：

```text
main/smart_home/services/smart_home_event_center.h
main/smart_home/services/smart_home_event_center.c
```

事件枚举：

```c
typedef enum {
    SH_EVENT_DEVICE_ONLINE = 0,
    SH_EVENT_DEVICE_OFFLINE,
    SH_EVENT_COMMAND_ACK,
    SH_EVENT_COMMAND_TIMEOUT,
    SH_EVENT_SENSOR_WARNING,
    SH_EVENT_FIRE_ALARM,
    SH_EVENT_RAIN_ALARM,
    SH_EVENT_HELP_ALARM,
    SH_EVENT_RULE_TRIGGERED,
    SH_EVENT_NETWORK_RECOVERED,
} smart_home_event_type_t;
```

结构：

```c
typedef struct {
    smart_home_event_type_t type;
    uint8_t floor_id;
    uint8_t severity;
    uint16_t seq;
    int64_t time_ms;
    char message[96];
} smart_home_event_t;
```

API：

```c
void smart_home_event_center_init(void);
void smart_home_event_post(smart_home_event_type_t type, uint8_t floor_id, uint8_t severity, uint16_t seq, const char *message);
uint16_t smart_home_event_count(void);
bool smart_home_event_at(uint16_t index, smart_home_event_t *out);
```

内部保存最近 32 条事件：

```c
#define SH_EVENT_HISTORY_MAX 32
static smart_home_event_t s_history[SH_EVENT_HISTORY_MAX];
static uint16_t s_write_index;
static uint16_t s_count;
```

post 后：

```c
ui_event_publish(UI_EVENT_MODEL_UPDATED);
```

火灾事件继续调用现有：

```c
smart_home_alarm_ui_set_fire(floor_id, active);
Application::GetInstance().Schedule(... app.Alert(...); app.WakeWordInvoke("fire_alarm"););
```

### 5.2 接入传感器状态

文件：`mqtt_device_model.c`

在 `device_model_apply_heartbeat()` 中，火灾状态变化时：

```c
if (heartbeat->fire_status >= 2) {
    smart_home_event_post(SH_EVENT_FIRE_ALARM, floor_id, 2, 0, "Fire alarm detected");
}
```

雨天：

```c
if (heartbeat->rain_status != 0) {
    smart_home_event_post(SH_EVENT_RAIN_ALARM, floor_id, 1, 0, "Rain detected");
}
```

求助：

```c
if (heartbeat->help_status != 0) {
    smart_home_event_post(SH_EVENT_HELP_ALARM, floor_id, 2, 0, "Help button pressed");
}
```

### 5.3 自动化规则

新增：

```text
main/smart_home/services/rule_engine.h
main/smart_home/services/rule_engine.c
```

API：

```c
void rule_engine_init(void);
void rule_engine_on_event(const smart_home_event_t *event);
```

规则：

- 火灾：关闭继电器，打开窗/天窗，触发语音告警。
- 雨天：收衣杆，关闭天窗。
- 离线：UI 标红，不自动控制。

调用示例：

```c
mqtt_send_command_v3(floor_id, IOT_CMD_SET_SERVO, 8, 0, IOT_SOURCE_RULE);
```

## 6、阶段六：LVGL 答辩级展示

### 6.1 总览页

文件：`page_data.c`

必须包含四块：

- 系统摘要：在线设备、在线传感器、MQTT 状态。
- 能耗电费：今日用电、今日电费、累计电费、实时功率。
- 安全状态：火灾、雨天、求助、离线。
- 最近事件：展示 `smart_home_event_at()` 最近 5 条。

新增事件时间线函数：

```c
static void event_timeline(lv_obj_t *page, data_ctx_t *ctx);
static void update_event_timeline(data_ctx_t *ctx);
```

每条事件显示：

```text
13:45 三楼 火灾告警
13:47 二楼 雨天收衣
```

### 6.2 控制页

文件：`page_ctrl.c`

每个按钮必须显示：

- 在线/离线。
- 开/关。
- pending/成功/失败状态。
- 今日费用。

事务状态来自 `sh_transaction`。新增 helper：

```c
const sh_transaction_t *sh_transaction_find_latest_for_device(uint8_t floor, uint8_t cmd, uint8_t index);
```

按钮文案：

```text
待确认...
执行成功
执行超时
今日 ¥0.03
```

### 6.3 设置页

文件：`page_set.c`

必须能设置：

- 电价。
- 设备额定功率。
- 清空今日电费。
- 进入离线演示。
- 清空事件日志。

确认弹窗复用当前 `show_info_modal()`，但清空类动作必须做二次确认。

## 7、阶段七：MCP 工具完整升级

### 7.1 工具清单

文件：`smart_home_mcp_tool.cc`

最终工具：

```text
self.iot.get_status
self.iot.get_sensors
self.iot.get_events
self.iot.get_transactions
self.iot.discover
self.iot.set_light
self.iot.set_relay
self.iot.set_servo_by_index
self.iot.all_off
self.iot.all_on
self.iot.all_lights_off
self.iot.all_lights_on
self.energy.get_summary
self.energy.get_devices
self.energy.set_tariff
self.energy.reset_today
self.demo.set_enabled
self.demo.trigger_fire
self.demo.trigger_rain
```

### 7.2 控制类返回值

控制工具不能返回裸 `true`，返回：

```json
{
  "accepted": true,
  "seq": 12,
  "state": "pending",
  "message": "command sent, waiting for ACK"
}
```

代码：

```cpp
uint16_t seq = mqtt_send_command_v3(floor, IOT_CMD_SET_LIGHT, index, on ? 1 : 0, IOT_SOURCE_MCP);
cJSON* root = cJSON_CreateObject();
cJSON_AddBoolToObject(root, "accepted", seq != 0);
cJSON_AddNumberToObject(root, "seq", seq);
cJSON_AddStringToObject(root, "state", seq ? "pending" : "failed");
return root;
```

## 8、阶段八：从机 common 化

### 8.1 只在主机闭环稳定后执行

新增：

```text
slave/slave_common/
  app_mqtt.c/.h
  app_protocol.c/.h
  app_heartbeat.c/.h
  app_control.c/.h
  app_sensor.c/.h
```

每个楼层保留：

```text
floor_config.h
main.c
CMakeLists.txt
```

### 8.2 common 配置结构

```c
typedef struct {
    uint8_t floor_id;
    const char *device_name;
    uint8_t light_count;
    uint8_t relay_count;
    uint8_t servo_count;
    const gpio_num_t *light_gpios;
    const gpio_num_t *relay_gpios;
    const gpio_num_t *servo_gpios;
} floor_config_t;
```

每层实现：

```c
const floor_config_t *Floor_Config_Get(void);
```

common MQTT 读取：

```c
const floor_config_t *cfg = Floor_Config_Get();
```

## 9、阶段九：测试与验收

### 9.1 编译

主机：

```powershell
idf.py build
```

三从机：

```powershell
idf.py -B build/slave_first -C slave/xiaozhi_slave_Firstfloor build
idf.py -B build/slave_second -C slave/xiaozhi_slave_Secondfloor build
idf.py -B build/slave_third -C slave/xiaozhi_slave_Thirdfloor build
```

### 9.2 必测场景

- 开灯 10 秒，今日电费增加。
- 关灯后电费停止增加。
- 重启后累计电费恢复。
- 修改电价后后续费用按新电价算。
- MQTT ACK 丢失时，UI 显示超时。
- MQTT 断开时，设备离线且计费暂停。
- 离线演示模式下，三层楼能模拟在线、火灾、雨天、控制。
- 小智查询“今天用了多少钱”返回 MCP 能耗摘要。

### 9.3 量化指标

| 指标 | 目标 |
|---|---:|
| 主机冷启动 | 20 次成功率 >= 95% |
| MQTT 控制闭环 | 300 次成功率 >= 98% |
| ACK 超时识别 | 3 秒内 |
| 从机离线识别 | 60 秒内 |
| UI 连续切页 | 50 次无崩溃 |
| 设备连续开关 | 100 次费用不重复累计 |
| 长稳运行 | 6 小时无重启 |

## 10、最终实施 Checklist

- [ ] 新增能耗模型字段。
- [ ] 新增 `energy_meter` 和 `energy_storage`。
- [ ] ACK/心跳确认后才触发计费。
- [ ] LVGL 总览显示电费汇总。
- [ ] LVGL 控制页显示单设备费用。
- [ ] LVGL 设置页支持电价和清空。
- [ ] MCP 增加 `self.energy.*`。
- [ ] 协议增加 V3 command/ack。
- [ ] 主机事务表上线。
- [ ] 从机发送 V3 ACK。
- [ ] 网络诊断服务上线。
- [ ] 离线演示服务上线。
- [ ] 事件中心上线。
- [ ] 火灾/雨天/求助事件进入时间线。
- [ ] MCP 控制类返回 seq 和 pending 状态。
- [ ] 三从机 common 化。
- [ ] 完成 6 小时稳定性测试。
- [ ] 输出国赛测试报告和演示脚本。

## 11、完成定义

当以下条件全部满足，可以认为项目达到“国一候选级软件完成态”：

- 设备控制不是乐观更新，而是 ACK/心跳确认。
- LVGL 能展示设备、传感、网络、告警、电费、事件。
- 小智能查询状态、控制设备、解释告警、查询电费。
- 无网络时可进入离线演示模式。
- 三个从机真实或模拟都能跑完整流程。
- 所有关键指标有测试数据，不靠口头描述。
- 答辩能讲清楚“感知 -> 控制 -> ACK -> 状态 -> 电费 -> 告警 -> 语音解释 -> 日志证明”的完整闭环。

