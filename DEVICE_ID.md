# Device ID 设计文档

## 概述

Device ID 是 OrchardGrid 用于唯一标识每个物理设备的标识符。

## 生成逻辑

### iOS/iPadOS
```swift
#if os(iOS)
  let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
#endif
```

**使用 `identifierForVendor`：**
- Apple 官方推荐的设备标识符
- 同一个 vendor（开发者）的所有 App 共享相同的 ID
- 卸载所有该 vendor 的 App 后，ID 会重置
- 重新安装 App 后，会生成新的 ID

### macOS
```swift
#else
  let id = UUID().uuidString
#endif
```

**使用随机 UUID：**
- macOS 没有 `identifierForVendor`
- 每次首次运行生成一个随机 UUID
- 存储在 UserDefaults 中持久化

## 持久化

```swift
let key = "com.orchardgrid.deviceID"

// 首次运行：生成并保存
if let saved = UserDefaults.standard.string(forKey: key) {
  return saved
}

let id = /* 生成逻辑 */
UserDefaults.standard.set(id, forKey: key)
return id
```

**特点：**
- 存储在 UserDefaults 中
- App 重启后保持不变
- 卸载 App 后会丢失（iOS）
- 重装 App 后会生成新 ID

## Device ID 的含义

### 1. 唯一标识物理设备
```
Device ID = 物理设备 + App 安装实例

同一台 iPhone：
  - 首次安装：Device ID = "ABC-123"
  - 卸载重装：Device ID = "DEF-456" (新 ID)
```

### 2. 区分用户的不同设备
```
用户 A:
  - iPhone: Device ID = "ABC-123"
  - iPad: Device ID = "DEF-456"
  - Mac: Device ID = "GHI-789"

用户 B:
  - iPhone: Device ID = "JKL-012"
  - Mac: Device ID = "MNO-345"
```

### 3. 数据库关系
```sql
CREATE TABLE devices (
  id TEXT PRIMARY KEY,           -- Device ID
  user_id TEXT NOT NULL,         -- 所属用户
  platform TEXT NOT NULL,        -- 平台 (iOS, macOS)
  os_version TEXT,               -- 系统版本
  status TEXT NOT NULL,          -- 状态 (online, offline, busy)
  last_heartbeat INTEGER,        -- 最后心跳时间
  tasks_processed INTEGER,       -- 处理的任务数
  failure_count INTEGER,         -- 失败次数
  created_at INTEGER NOT NULL,   -- 创建时间
  updated_at INTEGER NOT NULL    -- 更新时间
);
```

**关系：**
- 一个用户可以有多个设备
- 一个设备只属于一个用户
- Device ID 是全局唯一的

## 使用场景

### 1. WebSocket 连接
```swift
let deviceID = DeviceID.current
let serverURL = "\(wsURL)/device/connect?deviceId=\(deviceID)&userId=\(userID)"
```

**用途：**
- 后端识别连接的设备
- 分配任务到特定设备
- 追踪设备状态

### 2. 设备管理
```swift
// 获取用户的所有设备
GET /devices
Authorization: Bearer <JWT_TOKEN>

Response:
[
  {
    "id": "ABC-123",
    "user_id": "user-1",
    "platform": "ios",
    "status": "online",
    ...
  },
  {
    "id": "DEF-456",
    "user_id": "user-1",
    "platform": "macos",
    "status": "offline",
    ...
  }
]
```

### 3. 任务分配
```typescript
// 后端选择空闲设备处理任务
const idleDevices = Array.from(this.devices.values())
  .filter(d => d.status === "idle");

if (idleDevices.length > 0) {
  const device = idleDevices[0];
  device.status = "busy";
  device.websocket.send(JSON.stringify(task));
}
```

## 设计考虑

### 优点
1. ✅ **简单可靠**：使用 Apple 官方 API
2. ✅ **隐私保护**：不使用硬件标识符（MAC 地址等）
3. ✅ **跨平台一致**：iOS 和 macOS 都有实现
4. ✅ **持久化**：App 重启后保持不变

### 缺点
1. ❌ **重装后变化**：卸载重装 App 会生成新 ID
2. ❌ **无法跨设备同步**：同一用户的不同设备有不同 ID
3. ❌ **macOS 随机性**：macOS 使用随机 UUID

### 替代方案

#### 方案 A：使用硬件标识符
```swift
// ❌ 不推荐：隐私问题
let id = getMACAddress()  // MAC 地址
let id = getSerialNumber()  // 序列号
```

**问题：**
- 违反 Apple 隐私政策
- App Store 审核可能被拒

#### 方案 B：使用 iCloud KeyChain
```swift
// ✅ 可行：跨设备同步
let id = getFromiCloudKeychain()
```

**优点：**
- 卸载重装后保持不变
- 可以跨设备同步

**缺点：**
- 需要用户登录 iCloud
- 实现复杂

#### 方案 C：服务器生成
```swift
// ✅ 可行：服务器控制
let id = await registerDevice(userId: userId)
```

**优点：**
- 服务器完全控制
- 可以实现更复杂的逻辑

**缺点：**
- 需要网络请求
- 首次连接前无法获取

## 当前实现评估

### 适用场景
- ✅ 追踪设备状态
- ✅ 任务分配
- ✅ 设备管理
- ✅ 统计分析

### 不适用场景
- ❌ 设备认证（应使用 JWT）
- ❌ 跨设备同步（应使用用户 ID）
- ❌ 永久设备标识（会在重装后变化）

## 建议

### 短期（当前实现）
保持现有实现，因为：
1. 满足当前需求
2. 符合 Apple 隐私政策
3. 实现简单可靠

### 长期（未来优化）
考虑使用 iCloud KeyChain：
1. 卸载重装后保持不变
2. 更好的用户体验
3. 可以跨设备同步（可选）

## 总结

**Device ID 的本质：**
- 标识 App 的安装实例
- 不是永久的硬件标识符
- 用于运行时设备管理
- 与用户 ID 配合使用

**关键点：**
- Device ID ≠ 硬件 ID
- Device ID = App 安装实例 ID
- 一个用户可以有多个 Device ID
- 一个 Device ID 只属于一个用户

