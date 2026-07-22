# Uniapp蓝牙SDK说明1

## 1\. 接入方式

[demo地址](https://doc.runmefitserver.cn/uniapp-sdk-demo.rar?version=1.1.2)  
[sdk包地址](https://doc.runmefitserver.cn/uniapp-sdk.rar?version=1.1.2)  
将 sdk 导入到项目 libs 目录下

## 2\. 用到的权限

##### 蓝牙权限

##### 定位权限（部分安卓需要）

## 3\. sdk.notify方法返回的数据结构：Promise(resolve, reject)

##### resolve

| 属性 | 类型 | 说明 |
| :---- | :---- | :---- |
| status | number | 返回的状态码，只返回0，出错了会通过reject传出 |
| type | NotifyType | 返回的消息类型 |
| ... | ... | 每个方法返回的不同剩余参数 |

##### reject

| 属性 | 类型 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| code | string | 错误码 | 1 2 3 4 5 |
| message | string | 错误信息 | 1："命令码错误" 2: "校验码错误" 3: "数据长度错误" 4:"数据无效" 5:"指令收发超时错误" |

## 4\. 接口使用方式

##### 4.1 使用流程图：

连接成功  
连接中  
连接失败  
蓝牙连接  
连接状态  
修改MTU  
重新连接  
打开NOTIFY  
requestMTU  
设置分包传输最大值为mtuSize \- 3  
onBLECharacteristicValueChange  
将设备返回值传入SDK解析  
用户用SDK封装byteArray  
向设备发送byteArray

##### 4.2 在Uniapp蓝⽛回调函数Uni.onBLECharacteristicValueChange()中将设备回复的蓝⽛包传⼊sdk：

ts

uni.onBLECharacteristicValueChange((res) \=\> {  
   sdk.notify(res.value as unknown as ArrayBuffer).then((res) \=\> {  
      // 通过返回的res.type判断返回类型  
     if (res.type \== NotifyType.Pair) {  
      console.log(res.pairStatus ? "配对成功" : "配对失败");  
     }  
     if (res.type \== NotifyType.GetState) {  
      console.log("getState" \+ "-----------", res);  
     }  
    })  
    .catch((err) \=\> {  
     console.log(err.message);  
    });

}

##### 4.3 使用sdk封装给设备发送的数据:

ts

//如配对指令，其他指令都可在sdk实例上找到

const buffer: ArrayBuffer \= sdk.pair()

## 5\. 各指令及返回参数说明：

#### 5.1 配对指令：

* 5.1.1 普通设备配对

###### request：

sdk.pair()

###### response：

json

{  
    "status": 0,  
    "pairStatus": 0,  
    "type":NotifyType.Pair

}

* 5.1.2 GTS10配对

###### request:

sdk.pairGts10(usePopup: boolean)

###### response:

{  
    "status": 0,  
    "pairStatus": 0,  
    "type":NotifyType.Pair

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| pairStatus | number | 配对码 | 1：确定，0：取消 |
| usePopup | boolean | 是否弹窗（GTS10专用） |  |
| type | NotifyType | 返回类型 |  |

---

#### 5.2 设备状态（双向）：

* 5.2.1 获取设备状态：

###### request：

sdk.getState()

###### response：

json

{  
    "status": 0,  
    "timeFormat": 1,  
    "unitFormat":  1,  
    "tempFormat": 1,  
    "language":0,  
    "backlighting":5,  
    "screen":70,  
    "wristUp":true,  
    "type": NotifyType.GetState

}

* 5.2.2 设置设备状态：

###### request：

js

sdk.setState({      
    timeFormat: number,      
    unitFormat: number,      
    tempFormat: number,      
    language: number,      
    backlighting: number,      
    screen: number,      
    wristUp: boolean

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SetState

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| timeFormat | number | 时间制 | 0：24小时制，1：12小时制 |
| unitFormat | number | 公英制 | 0：公制，1：英制 |
| tempFormat | number | 温度制 | 0：摄氏，1：华氏 |
| language | number | 语言 | 0中文简，1中文繁，2英文，3俄语，4法语，5西班牙语，6德语，7日语，8意大利语，9韩语，10,荷兰语，11泰语 |
| backlighting | number | 背光时长(秒为单位) |  |
| screen | number | 屏幕亮度(百分比) |  |
| wristUp | boolean | 抬手亮开关 |  |

---

#### 5.3 查找设备（双向）：

* 5.3.1 查找设备：

###### request：

ts

sdk.findPhone(isFind:boolean)

###### no response：

* 5.3.2 查找手机：

###### no request：

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.FindPhone,  
    "isFind": true

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| isFind | boolean | 查找方式 | true: 查找，false:停止查找 |

---

#### 5.4 拍照控制（双向）：

* 5.4.1 手机控制设备：

###### request：

ts

sdk.cameraControl(cameraControlType: CameraControlType)

###### no response：

* 5.4.2 设备控制手机：

###### no request：

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.CameraControl,  
    "controlType": CameraControlType.CameraIn

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| cameraControlType | CameraControlType | 控制方式 | CameraIn: 进入拍照界面 CameraExit: 退出拍照界面 TakePhoto：摇一摇拍照 |

---

#### 5.5 来电控制（双向）：

* 5.5.1 手机控制设备：

###### request：

ts

sdk.phoneControl({  
    callControlType: CallControlType,  
    number: string,  
    isNumber: boolean

})

###### no response

* 5.5.2 设备控制手机：

###### no request：

###### response：

json

{  
    "callControlType": "HangUp",  
    "value":"13700000000",  
    "type": NotifyType.PhoneControl,  
    "status": 0

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| callControlType | CallControlType or string | 控制方式 | HangUp: 挂断 Answer: 接听 Incoming：来电 Exit：去电 |
| number | string | 姓名或手机号 |  |
| isNumber | boolean | 是否为手机号 |  |
| value | string | 同number |  |

---

#### 5.6 获取电池电量指令：

###### request：

sdk.getPower()

###### response：

json

{  
    "status": 0,  
    "power": 75,  
    "isCharge":false,  
    "type": NotifyType.Power

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| power | number | 电量 |  |
| isCharge | boolean | 是否在充电 |  |

---

#### 5.7 获取版本信息：

###### request：

sdk.getVersion()

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.Version,  
    "version": "v1.0.1",  
    "uiVersion": "v1.0.1",  
    "bufferSize":4000,  
    "lcdWidth":240,  
    "lcdHeight":280,  
    "screenType":1,  
    "model":"X01G001",  
    "uiForceUpdate":false,  
    "uiSupportDifferentialUpgrade":false,  
    "supportSugar":false,  
    "protocolVersion": "v1.0.1",  
    "supportNewSleepAlgorithm": true,  
    "newSleepShowWay": 1,  
    "supportSleepNotice": false,  
    "supportUnbind": false

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| version | string | 固件版本号 |  |
| uiVersion | string | ui版本号 |  |
| bufferSize | number | 设备缓冲区大小 |  |
| lcdWidth | number | 设备lcd宽 |  |
| lcdHeight | number | 设备lcd高 |  |
| screenType | number | 屏幕类型 | 0：圆屏，1：方屏 |
| model | string | 设备批次号 |  |
| uiForceUpdate | boolean | ui是否强制升级 |  |
| uiSupportDifferentialUpgrade | boolean | ui是否支持差分升级 |  |
| supportSugar | boolean | 是否支持血糖 |  |
| protocolVersion | string | 协议版本 |  |
| supportNewSleepAlgorithm | boolean | 是否支持新睡眠算法 |  |
| newSleepShowWay | number | 睡眠新统计展示方式 | 0：原来方式（18：00-18:00） 1：起床在哪天则整段睡眠属于哪天 |
| supportSleepNotice | boolean | 是否支持睡眠提醒 |  |
| supportUnbind | boolean | 是否支持app解绑指令 |  |

---

#### 5.8 设置时间时区：

###### request：

ts

sdk.setTime(date: Date)

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SetTime

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| date | Date | 时间 |  |

---

#### 5.9 设置用户信息：

###### request：

ts

sdk.setUserInfo({  
    sex: number,  
    age: number,  
    height: number,  
    weight: number

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SetUserInfo

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| sex | number | 性别 | 0：女，1：男 |
| age | number | 年龄 |  |
| height | number | 身高（单位CM） |  |
| weight | number | 体重（单位0.1 KG） |  |

---

#### 5.10 一天运动目标指令（双向）：

* 5.10.1 获取一天运动目标：

###### request：

ts

sdk.getGoals()

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.GetGoals,  
    "steps": 100,  
    "heat": 100,  
    "distance": 100

}

* 5.10.2 设置一天运动目标：

###### request：

ts

sdk.setGoals({      
    steps: number,      
    heat: number,      
    distance: number

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SetGoals

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| steps | number | 计步目标 (0-65535) |  |
| heat | number | 热量目标(千卡) (0-65535) |  |
| distance | number | 距离目标(千米) (0-65535) |  |

---

#### 5.11 获取当前设备展示数据：

###### request：

ts

sdk.getHealthDetail()

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.HealthDetail,  
    "totalSteps": 100,  
    "totalHeat": 100,  
    "totalDistance": 100,  
    "totalSleep":8122,  
    "totalDeepSleep":7000,  
    "totalLightSleep":1122,  
    "currentHeartRate":80,  
    "currentFz": 82,  
    "currentSs": 127,  
    "currentBloodOxygen": 100,  
    "currentPressure": 30,  
    "currentMet": 3,  
    "currentMai":76,  
    "currentTemp": 30,  
    "currentBloodSugar":56,  
    "isWear":1,  
    "breatheRate": 50,

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| totalSteps | number | 总计步 |  |
| totalHeat | number | 总热量(千卡) |  |
| totalDistance | number | 总距离(千米) |  |
| totalSleep | number | 总睡眠(分钟) |  |
| totalDeepSleep | number | 深睡（分钟） |  |
| totalLightSleep | number | 浅睡（分钟） |  |
| currentHeartRate | number | 当前心率（次/分钟） |  |
| currentFz | number | 当前血压舒张压 |  |
| currentSs | number | 当前血压收缩压 |  |
| currentBloodOxygen | number | 当前血氧饱和度 |  |
| currentPressure | number | 当前压力 |  |
| currentMet | number | 当前梅脱 |  |
| currentMai | number | 当前MAI |  |
| currentTemp | number | 当前体温（0.1摄氏度） |  |
| currentBloodSugar | number | 当前血糖（0.1） |  |
| isWear | number | 是否佩戴，1:佩戴，0:脱腕，（-1/255）:无效 |  |
| breatheRate | number | 呼吸率 |  |

---

#### 5.12 健康数据检测开关（双向）：

* 5.12.1 获取健康数据检测开关：

###### request：

ts

sdk.getHealthOpen()

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.GetHealthOpen,  
    "heartRate": true,  
    "bloodPressure": true,  
    "bloodOxygen": true,  
    "pressure": true,  
    "temp": true,  
    "bloodSugar":true,  
    "breathRate": false

}

* 5.12.2 设置健康数据检测开关：

###### request：

ts

sdk.setHealthOpen({      
    heartRate: boolean,      
    bloodPressure: boolean,      
    bloodOxygen: boolean,  
    pressure: boolean,  
    temp: boolean,  
    bloodSugar:boolean

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SetHealthOpen

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| heartRate | boolean | 心率开关 |  |
| bloodPressure | boolean | 血压开关 |  |
| bloodOxygen | boolean | 血氧开关 |  |
| pressure | boolean | 压力开关 |  |
| temp | boolean | 温度开关 |  |
| bloodSugar | boolean | 血糖开关 |  |
| breatheRate | boolean | 呼吸率开关 |  |

---

#### 5.13 恢复出厂设置：

###### request：

ts

sdk.reset()

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.Reset

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |

---

#### 5.14 设备关机

###### request

js

sdk.closeDevice()

###### response

json

{  
    "status": 0,  
    "type": NotifyType.CloseDevice

}

###### 字段说明

| 字段 | 属性 | 说明 |
| :---- | :---- | :---- |
| status | number | 状态码 |
| type | NotifyType | 返回类型 |

---

#### 5.15 设置单独时区

###### request

ts

sdk.setTimeOffset(offsetMinute: number)

###### response

json

{  
    "status": 0,  
    "type": NotifyType.SetTimeOffset

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| offsetMinute | number | 时区（分钟为单位，带符号）UTC+8 \=\> \+480 |  |

---

#### 5.16 设置PPG检测开关

###### request:

ts

sdk.setPPGOpen(openPPG:boolean)

###### response:

json

{  
	"status": 0,  
	"tpye": NotifyType.SetPPGOpen

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |

---

#### 5.17 Bt蓝牙连接断开指令

###### request

ts

sdk.setBtStatus(isConnect: boolean)

###### response

json

{  
	"status": 0,  
	"type": NotifyType.SetBtStatus

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |

---

#### 5.18 清除logo

###### request

ts

sdk.clearLogo()

###### response

json

{  
    "status": 0,  
    "type": NotifyType.ClearLogo,

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |

---

#### 5.19 设置心率报警阈值

###### request

ts

sdk.setHeartRateAlarmThreshold({  
	isOpen: boolean,  
	threshold: number

})

###### response

json

{  
	"status": 0,  
	"type": NotifyType.SetHeartRateAlarm

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| isOpen | boolean | 是否开启 |  |
| threshold | number | 心率阈值 |  |

---

#### 5.20 设置进入退出演示模式

###### request

ts

sdk.setDisplayMode(isDisplay: boolean)

###### response

json

{  
	"status": 0,  
	"type": NotifyType.DisplayMode

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| isDisplay | boolean | 是否进入演示模式 |  |

---

#### 5.21 设置进入退出船运模式

###### request

ts

sdk.setShipMode(isOpen: boolean)

###### response

json

{  
	"status": 0,  
	"type": NotifyType.ShipMode

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| isOpen | boolean | 是否进入船运模式 |  |

---

#### 5.22 心率检测间隔和范围（双向）：

* 5.22.1 获取心率检测间隔和范围：

###### request：

ts

sdk.getHeartRateControl()

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.GetHeartRate,  
    "startHour": 0,  
    "startMinute":  0,  
    "endHour": 0,  
    "endMinute":0,  
    "period":0,  
    "alarmThreshold":0,  
    "oxygenPeriod": 0

}

* 5.22.2 设置心率检测间隔和范围：

###### request：

ts

sdk.setHeartRateControl({      
    startHour: number,      
    startMinute: number,      
    endHour: number,      
    endMinute: number,      
    period: number,      
    alarmThreshold: number

})

（批次号：X01M01T013专用）

ts

sdk.setHeartRateControlWithOxygen({      
    startHour: number,      
    startMinute: number,      
    endHour: number,      
    endMinute: number,      
    period: number,      
    alarmThreshold: number,  
    oxygenPeriod: number

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SetHeartRate

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| startHour | number | 开始小时 |  |
| startMinute | number | 开始分钟 |  |
| endHour | number | 结束小时 |  |
| endMinute | number | 结束分钟 |  |
| period | number | 周期(分钟为单位) |  |
| alarmThreshold | number | 报警阈值(百分比) |  |
| oxygenPeriod | number | 血氧检测周期(以分钟为单位， 批次号：X01M01T013专用) |  |

---

#### 5.23 常用联系人（双向）：

注：设备最多存20个常用联系人

* 5.23.1、 获取常用联系人：

###### request：

ts

sdk.getContacts()

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.GetContact,  
    "contacts":\[  
        {  
            "name":"张三",  
            "number":"123123123122"  
        },  
        {  
            "name":"李四",  
            "number":"123123123422"  
        }  
    \]

}

* 5.23.2 设置常用联系人：

###### request：

ts

sdk.setContacts(contacts: Array\<Contact\>)

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SetContact

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| contacts | Array | 常用联系人数组 |  |
| contact.name | string | 姓名 |  |
| contact.number | string | 电话 |  |

---

#### 5.24 紧急联系人（双向）：

注：设备最多存3个紧急联系人

* 5.24.1、 获取紧急联系人：

###### request：

ts

sdk.getSos()

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.GetSos,  
    "contacts":\[  
        {  
            "name":"张三",  
            "number":"123123123122"  
        },  
        {  
            "name":"李四",  
            "number":"123123123422"  
        }  
    \]

}

* 5.24.2 设置紧急联系人：

###### request：

ts

sdk.setSos(sos: Array\<Contact\>)

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SetSos

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| sos | Array | 紧急联系人数组 |  |
| contact.name | string | 姓名 |  |
| contact.number | string | 电话 |  |

---

#### 5.25 勿扰模式（双向）：

* 5.25.1 获取勿扰模式：

###### request：

ts

sdk.getNotDisturb()

###### response：

json

{  
    "status": 0,   
    "type": NotifyType.GetNotDisturb,  
    "allDayOnOff":false,  
    "onOff":false,  
    "startHour":0,  
    "startMinute":0,  
    "endHour":23,  
    "endMinute":59

}

* 5.25.2 设置勿扰模式：

###### request：

ts

sdk.setNotDisturb({  
        onOff: boolean,  
        allDayOnOff: boolean,  
        startHour: number,  
        startMinute: number,  
        endHour: number,  
        endMinute: number

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SetNotDisturb

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| allDayOnOff | boolean | 全天勿扰开关 |  |
| onOff | boolean | 定时勿扰开关 |  |
| starHour | number | 开始小时 |  |
| startMinute | number | 开始分钟 |  |
| endHour | number | 结束小时 |  |
| endMinute | number | 结束分钟 |  |

---

#### 5.26 闹钟（双向）：

* 5.26.1 获取闹钟：

###### request：

ts

sdk.getClocks()

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.GetClocks,  
    "clockList":\[  
        {  
            "hour":18,  
            "minute":0,  
            "onOff":true,  
            "repeats":\[0,1,1,1,1,1,0\],  
            "clockType":0  
        }   
    \]

}

* 5.26.2 设置闹钟：

###### request：

ts

sdk.setClocks(clocks: Array\<Clock\>)

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SetClocks

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| clockList | Array | 闹钟列表 |  |
| clock.hour | number | 小时 |  |
| clock.minute | number | 分钟 |  |
| clock.onOff | boolean | 闹钟开关 |  |
| clock.repeats | Array | 星期重复开关（第一位从周天开始） | 1:开 0:关 |
| clock.clockType | number | 类型（暂无意义） |  |

#### 5.27 久坐提醒（双向）：

* 5.27.1 获取久坐提醒：

###### request：

ts

sdk.getLongSit()

###### response：

json

{  
    "status": 0,   
    "type": NotifyType.GetLongSit,  
    "onOff":false,  
    "startHour":0,  
    "startMinute":0,  
    "endHour":23,  
    "endMinute":59,  
    "interval":60

}

* 5.27.2 设置久坐提醒：

###### request：

ts

sdk.setLongSit({  
        onOff: boolean,  
        startHour: number,  
        startMinute: number,  
        endHour: number,  
        endMinute: number,  
        interval: number

})

###### response：

json

{  
    "status": 0  
    "type": NotifyType.SetLongSit

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| onOff | boolean | 提醒开关 |  |
| startHour | number | 开始小时 |  |
| startMinute | number | 开始分钟 |  |
| endHour | number | 结束小时 |  |
| endMinute | number | 结束分钟 |  |
| interval | number | 提醒间隔（分钟） |  |

---

#### 5.28 喝水提醒（双向）：

* 5.28.1 获取喝水提醒：

###### request：

ts

sdk.getDrinkWater()

###### response：

json

{  
    "status": 0,   
    "type": NotifyType.GetDrinkWater,  
    "onOff":false,  
    "startHour":0,  
    "startMinute":0,  
    "endHour":23,  
    "endMinute":59,  
    "interval":60

}

* 5.28.2 设置喝水提醒：

###### request：

ts

sdk.setDrinkWater({  
    onOff: boolean,  
    startHour: number,  
    startMinute: number,  
    endHour: number,  
    endMinute: number,  
    interval: number

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SetDrinkWater

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| onOff | boolean | 提醒开关 |  |
| startHour | number | 开始小时 |  |
| startMinute | number | 开始分钟 |  |
| endHour | number | 结束小时 |  |
| endMinute | number | 结束分钟 |  |
| interval | number | 提醒间隔（分钟） |  |

---

#### 5.29 推送消息：

###### request：

ts

sdk.sendMessage({  
 	messageType: MessageType,   
 	title: string,   
 	content: string

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SendMessage

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| messageType | MessageType | 消息类型 | 1:电话2:短信3:mail 4:Twitter 5:Facebook 6:WhatsApp 7:Line 8:Skype 9:QQ 10:wechat 11:Instagram 12:LinkedIn 13:Messenger 14:VK 15:Viber 16:Telegram 17:KakaoTalk 18:其他19:Threads 20:GroupMe 21:WHOO 22:Discord 23:Signal 24:钉钉 25:企业微信 26:飞书 |
| title | string | 标题 |  |
| content | string | 内容 |  |

---

#### 5.30 推送天气（今天和未来三天）：

###### request：

ts

sdk.setWeather(weatherDays: Array\<WeatherDay\>)

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SetWeather

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| weatherDays | Array | 天气列表（今天和未来三天） |  |
| weatherDay.temp | number | 当前温度 |  |
| weatherDay.maxTemp | number | 最高温度 |  |
| weatherDay.minTemp | number | 最低温度 |  |
| weatherDay.windSpeed | number | 风速 |  |
| weatherDay.dampness | number | 湿度 |  |
| weatherDay.seeing | number | 可见度 |  |
| weatherDay.airQuality | number | 空气质量 | 1优，2良，3差 |
| weatherDay.type | number | 类型 | 1、小雨，2、中雨，3、大雨，4、阴天，5、多云，6、晴，7、雾霾，8、台风，9、雷雨，10、冰雹，11、小雪，12、中雪，13、大雪，14、雨夹雪15、沙尘暴，16、雪加冰雹，17、狂风，18、大风，19、小风，20、龙卷风，21、热带风暴，22，雷暴，23，猛烈雷暴，24、未知 |

---

#### 5.31 音乐控制（双向）：

* 5.31.1 app控制设备：

###### request：

ts

sdk.musicControl({  
    playState: number,  
    volPercent: number,  
    ratePercent: number,  
    musicTitle: string,  
    lyric:string

})

###### no response：

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| playState | number | 播放器状态 | 0暂停1播放 |
| volPercent | number | 音量百分比 |  |
| ratePercent | number | 歌曲进度 |  |
| musicTitle | string | 歌名 |  |
| lyric | string | 歌词 |  |

*   
  5.31.2 设备控制app：

###### no request：

###### response：

json

{  
    "type": "NotifyType.MusicControl",  
    "musicControlType": 1

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| musicControlType | MusicControlType | 控制指令 | Play:播放（1） Stop:暂停（2） Continue:继续播放（3） Previous:上一首（4） Next:下一首（5） AddVol:音量+（6） SubVol:音量-（7） |

---

#### 5.32 事件提醒（双向）：

* 5.32.1 获取事件提醒：

###### request：

ts

sdk.getEventReminder()

###### response：

json

{  
    "status": 0,   
    "type": NotifyType.GetEventReminder,  
    "eventReminders":\[  
        {  
         "year":2025,  
         "month":2,  
         "day":6,  
         "hour":17,  
         "minute":26,  
         "content":"和朋友出去聚会",  
         "remindType":1,  
         "repeatType":1,  
         "repeats":\[1,1,0,0,0,0,1\],  
         "reminderIndex": 8  
        }  
    \]

}

* 5.32.2 设置事件提醒：（最多15个）

###### request：

ts

sdk.setEventReminder(reminders: \`Array\<EventReminder\>\`)

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SetEventReminder

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| eventReminders | Array | 事件列表 |  |
| eventReminder.year | number | 年 |  |
| eventReminder.month | number | 月 |  |
| eventReminder.day | number | 日 |  |
| eventReminder.hour | number | 小时 |  |
| eventReminder.minute | number | 分钟 |  |
| eventReminder.content | string | 内容 |  |
| eventReminder.remindType | number | 提醒类型 | 1、2、3、4 |
| eventReminder.repeatType | number | 重复类型 | 1：单次 2：天 3：周 4：月 5：年 |
| eventReminder.repeats | Array | 一周重复，第一位从周天开始 | 1：开 2：关 |
| eventReminder.reminderIndex | number | 事件索引 |  |

---

#### 5.33 设置设备运动显示列表（手环用）

* 5.33.1 获取设备运动显示列表：

###### request

ts

sdk.getSportModes()

###### response

json

{  
    "status": 0,  
    "type": NotifyType.GetSportModes,  
    "modes": \[1,2,3,4,5\]

}

* 5.33.2 设置设备运动显示列表

###### request

ts

sdk.setSportModes(\[1,2,5\])

###### response

json

{  
    "status": 0,  
    "type": NotifyType.SetSportModes,

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| modes | Array | 运动列表 | 0:户外跑步 1:户外骑行 2:跳绳 3:户外步行 4: 室内单车 5:室内跑步 6:健走 7: 徒步 8: 足球 9:羽毛球 10: 篮球 11:椭圆机 12: 瑜伽 13: 爬山 14: 力量训练 15:自由运动 |

---

#### 5.34 推送天气（当天及未来7天预报）

###### request

ts

sdk.setWeatherSeven({  
	weatherDays: Array\<WeatherDaySeven\>,  
	cityName: string

})

###### response

json

{  
 	"status": 0,  
 	"type": NotifyType.SetWeatherSeven

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| cityName | string | 城市名字 |  |
| weatherDays | Array\<WeatherDaySeven.\> | 天气数组 |  |
| weatherDaySeven.temp | number | 温度 |  |
| weatherDaySeven.maxTemp | number | 最高温 |  |
| weatherDaySeven.minTemp | number | 最低温 |  |
| weatherDaySeven.windSpeed | number | 风速 |  |
| weatherDaySeven.dampness | number | 湿度 |  |
| weatherDaySeven.seeing | number | 能见度 |  |
| weatherDaySeven.uv | number | 紫外线强度 |  |
| weatherDaySeven.airQuality | number | 空气质量 | 1优 2良 3差 |
| weatherDaySeven.type | number | 天气类型 | 1：小雨，2：中雨，3：大雨，4：阴天，5：多云，6：晴，7：雾霾，8：台风，9：雷雨，10：冰雹，11：小雪，12：中雪，13：大雪，14：雨夹雪15：沙尘暴，16：雪加冰雹，17：狂风，18：大风，19：小风，20：龙卷风，21：热带风暴，22，雷暴，23，猛烈雷暴，24：未知 |
| weatherDaySeven.sunriseHour | number | 日出时 |  |
| weatherDaySeven.sunriseMinute | number | 日出分 |  |
| weatherDaySeven.sunsetHour | number | 日落时 |  |
| weatherDaySeven.sunsetMinute | number | 日落分 |  |
| weatherDaySeven.moonriseHour | number | 月出时 |  |
| weatherDaySeven.moonriseMinute | number | 月出分 |  |
| weatherDaySeven.moonsetHour | number | 月落时 |  |
| weatherDaySeven.moonsetMinute | number | 月落分 |  |

---

#### 5.35 推送应用列表

* 5.35.1 获取推送应用列表

###### request

ts

sdk.getApps()

###### response

json

{  
 	"status": 0,  
 	"type": NotifyType.GetApps,  
 	"apps": Array\<number\>

}

* 5.35.2 设置推送应用列表

注：最大支持24个

###### request

ts

sdk.setApps(apps: Array\<number\>)

###### response

json

{  
 	"status": 0,  
 	"type": NotifyType.SetApps

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| apps | Array | 应用id列表 | 1：呼吸训练 2：梅脱 3：语音助手 4：计时器 5：秒表 6：计算器7：闹钟 8：手电筒 9：查找手机 10：世界时钟 11：番茄钟 12：女性健康 13：血糖 14：血压 15：MAI 16：压力 |

---

#### 5.36 设置世界时钟（双向）

* 5.36.1 获取世界时钟

###### request

ts

sdk.getWorldClocks()

###### response

json

{  
    "status": 0,   
    "type": NotifyType.GetWorldClocks,  
    "citys":\[1,2,3\]

}

* 5.36.2 设置世界时钟

###### request

ts

sdk.setWorldClocks(city： Array\<number\>)

###### response

json

{  
 	"status": 0,  
 	"type": NotifyType.SetWorldClocks

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| citys | Array | 城市ids | 1：北京 2：华盛顿 3：伦敦 4：巴黎 5：纽约 6：东京 7：上海 8：孟买 9：悉尼 10：洛杉矶 11：莫斯科 12：柏林 13：罗马 14：伊斯坦布尔 15：开罗 16：南京 17：温哥华 18：芝加哥 19：里约热内卢 20：阿姆斯特丹 21：新加坡 22：首尔 23：墨尔本 24：新德里 25：堪培拉 26：巴西利亚 27：墨西哥城 28：香港 29：斯德哥尔摩 30：巴塞罗那 31：慕尼黑 GTS10新增城市: 32：雅典 33：圣保罗 34：迈阿密 35：吉隆坡 36：赫尔辛基 37：苏黎世 38：布宜诺斯艾利斯 39：奥克兰 40：惠灵顿 41：马德里 42：阿布扎比 43：雅各布城 44：卡萨布兰卡 45：底特律 46：曼谷 47：迪拜 |

---

#### 5.37 设置密码和摘下锁定开关（GTS7）

* 5.37.1 获取密码

###### request

ts

sdk.getPassword()

###### response

json

{  
	"status": 0,  
	"type": NotifyType.GetPassword,  
	"isOpen": true,  
	"password": "123321"

}

* 5.37.2 设置密码

###### request

ts

sdk.setPassword({  
 	isOpen: true,  
 	password: "9999"

})

###### response

json

{  
 	"status": 0,  
 	"type": NotifyType.SetPasswords,

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| password | string | 纯数字密码，例"0012345" |  |
| isOpen | boolean | 开关 |  |

---

#### 5.38 女性健康(双向，GTS7)

* 5.38.1 获取经期信息

###### request

ts

sdk.getFemaleHealth()

###### response

json

{  
 	"status": 0,  
 	"type": NotifyType.GetFemaleHealth,  
 	"numberOfDays": 6,  
 	"cycleDays": 30,  
 	"lastPeriodYear": 2025,  
 	"lastPeriodMonth": 5,  
 	"lastPeriodDay": 15,  
 	"remindOnOff": true

}

* 5.38.2 设置经期信息

###### request

ts

sdk.setFemaleHealth({  
 	numberOfDays: number,  
 	cycleDays: number,  
 	lastPeriodYear: number,  
 	lastPeriodMonth: number,  
 	lastPeriodDay: number,  
 	remindOnOff: boolean

})

###### response

json

{  
 	"status": 0,  
 	"type": NotifyType.SetFemaleHealth

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| numberOfDays | number | 月经天数 |  |
| cycleDays | number | 月经周期 |  |
| lastPeriodYear | number | 上次经期年份 |  |
| lastPeriodMonth | number | 上次经期月份 |  |
| lastPeriodDay | number | 上次经期日期 |  |
| remindOnOff? | boolean | 提醒开关（GTS10用） |  |

---

#### 5.39 健康测量

###### request

ts

sdk.healthMeasurements({  
    healthType: HealthMeasureType.HeartRate,  
    onOff: true,

 })

###### response

json

{  
 	"status": 0,  
 	"type": NotifyType.HealthMeasure,  
 	"value": 50,  
 	"healthType": 102

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| healthType | HealthMeasureType | 测量类型 | (99)：心率 (102)：压力 |
| onOff | boolean | 测量开关 |  |

---

#### 5.40 设置世界时钟夏令时列表

* 5.40.1 获取世界时钟夏令时列表

###### request

ts

sdk.getSummerWorldClock()

###### response

json

{  
 "status": 0,  
 "type": NotifyType.GetSummerWorldClock,  
 "clocks": \[  
  		{  
   			"cityId": 5,  
        	"startMonth": 1,  
        	"startWeek": 2,  
        	"endMonth": 12,  
        	"endWeek": 1,  
        	"timeOffset": \-120  
  		}  
 	\]

}

* 5.40.2 设置世界时钟夏令时列表

###### request

ts

sdk.setSummerWorldClock(summerWorldClocks : Array\<SummerWorldClock\>)

###### response

json

{  
 	"status": 0,  
 	"type": NotifyType.SetSummerWorldClock

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| summerWorldClocks | Array |  |  |
| SummerWorldClock.cityId | number | 城市id | 1：北京 2：华盛顿 3：伦敦 4：巴黎 5：纽约 6：东京 7：上海 8：孟买 9：悉尼 10：洛杉矶 11：莫斯科 12：柏林 13：罗马 14：伊斯坦布尔 15：开罗 16：南京 17：温哥华 18：芝加哥 19：里约热内卢 20：阿姆斯特丹 21：新加坡 22：首尔 23：墨尔本 24：新德里 25：堪培拉 26：巴西利亚 27：墨西哥城 28：香港 29：斯德哥尔摩 30：巴塞罗那 31：慕尼黑 GTS10新增城市: 32：雅典 33：圣保罗 34：迈阿密 35：吉隆坡 36：赫尔辛基 37：苏黎世 38：布宜诺斯艾利斯 39：奥克兰 40：惠灵顿 41：马德里 42：阿布扎比 43：雅各布城 44：卡萨布兰卡 45：底特律 46：曼谷 47：迪拜 |
| SummerWorldClock.startMonth | number | 开始月份 |  |
| SummerWorldClock.startWeek | number | 开始星期 |  |
| SummerWorldClock.endMonth | number | 结束月份 |  |
| SummerWorldClock.endWeek | number | 结束星期 |  |
| SummerWorldClock.timeOffset | number | 夏令时偏移（有符号，分钟为单位） |  |

---

#### 5.41 运动数据双向同步

* 5.41.1 同步运动数据到设备

###### request:

ts

sdk.sportSyncToDevice({  
	sportType: number,  
	sportStatus: number,  
	sportDistance: number,  
	speed: number,  
	locationList: Array\<LocationData\>

})

###### response

json

{  
	"status": 0,  
	"type": NotifyType.SportSyncToDevice

}

* 5.41.2 接收设备的同步运动数据

###### no request

###### response

json

{  
	"status": 0,  
	"type": NotifyType.SportSyncFromDevice,  
	"sportType": 1,  
	"sportStatus": 2,  
	"steps": 5000,  
	"calorie": 500,  
	"paceTime": 10,  
	"cadence": 10,  
	"heartRate": 150,  
	"sportSecond": 3600

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| sportType | number | 运动类型 | 1:户外跑步 2:户外步行 3:户外骑行; 4:遛狗 |
| sportStatus | number | 运动状态 | 1:开启，2:进行中，3:暂停，4:运动继续，5:结束 |
| sportDistance | number | 距离(m) |  |
| speed | number | 速度(m/s，户外骑行) |  |
| locationList | Array | 经纬度数组 |  |
| LocationData.longitude | number | 经度(最多六位小数) |  |
| LocationData.latitude | number | 纬度(最多六位小数) |  |
| steps | number | 步数 |  |
| calorie | number | 卡路里（卡） |  |
| paceTime | number | 配速（min/Km） |  |
| cadence | number | 步频（steps/min） |  |
| heartRate | number | 心率 |  |
| sportSeconds | number | 运动时间（s） |  |

---

#### 5.42 睡眠提醒

* 5.42.1 获取睡眠提醒

###### request

ts

sdk.getSleepClock()

###### response

json

{  
	"status": 0,  
	"type": NotifyType.GetSleepClock,  
	"fallAsleepHour": 23,  
    "fallAsleepMinute": 0,  
    "fallAsleepOnOff": true,  
    "getUpHour": 6,  
    "getUpMinute": 0,  
    "getUpOnOff": true,  
    "onOff": false,  
    "repeats": \[  
        1,  
        1,  
        1,  
        1,  
        1,  
        0,  
        0  
    \]

}

* 5.42.2 设置睡眠提醒

###### request

ts

sdk.setSleepClock({  
	fallAsleepHour : number;  
	fallAsleepMinute : number;  
	fallAsleepOnOff: boolean;  
	getUpHour: number;  
	getUpMinute: number;  
	getUpOnOff: boolean;  
	onOff: boolean;  
	repeats: Array\<number\>;  
	reminderAdvanceMinute: number;

})

###### response

json

{  
	"status": 0,  
	"type": NotifyType.SetSleepClock

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| fallAsleepHour | number | 入睡提醒小时 |  |
| fallAsleepMintue | number | 入睡提醒分钟 |  |
| fallAsleepOnOff | boolean | 入睡提醒开关 |  |
| getUpHour | number | 起床提醒小时 |  |
| getUpMinute | number | 起床提醒分钟 |  |
| getUpOnOff | boolean | 起床提醒开关 |  |
| onOff | boolean | 总开关 |  |
| repeats | Array | 星期重复开关（第一位从周天开始） | 1:开 0：关 |
| reminderAdvanceMinute | number | 提前多久提醒（分钟） |  |

---

#### 5.43 获取设备语言列表

###### request

ts

sdk.getSupportLanguages()

###### response

json

{  
	"status": 0,  
	"type": NotifyType.SupportLanguages,  
	"languages": \[0,1,2,3,4,5,6,7\]

}

###### 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| languagaes | Array | 语言编码列表 | 0中文简，1中文繁，2英文，3俄语，4法语，5西班牙语，6德语，7日语，8意大利语，9韩语，10,荷兰语，11泰语，12越南语，13马来语，14印尼语，15葡萄牙语，16罗马尼亚语，17波兰语，18土耳其语，19蒙古语，20印地语 |

---

#### 5.44 同步运动数据：

###### request：

ts

sdk.getSportHistory(false)

注：一次获取一条，多条可多次调用此接口，sportLength大于1代表还有数据，可继续调用获取剩余数据

###### response：

json

{  
    "status": 0,  
    "sportLength":1,  
    "sportSeconds": 182,  
    "sportType": 1,  
    "currentSportId":1,  
    "currentSportDataLength":1000,  
    "year":2023,  
    "month":2,  
    "day":6,  
    "hour":19,  
    "minute":16,  
    "second":30,  
    "steps":1000,  
    "distance":1000,  
    "speed":1,  
    "calorie":1000,  
    "paceTime":300,  
    "stepFrequency":10,  
    "heartRateLength":3,  
    "heartRateAvg": 80,  
    "heartRateList":\[100,90,80\],  
    "locationLength": 0,  
    "locations": \[\]

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| sportLength | number | 运动总个数 |  |
| sportSeconds | number | 运动时间(s) |  |
| currentSportId | number | 当前运动ID |  |
| currentSportDataLength | number | 当前运动数据长度 |  |
| year | number | 年 |  |
| month | number | 月 |  |
| day | number | 日 |  |
| hour | number | 小时 |  |
| minute | number | 分钟 |  |
| second | number | 秒 |  |
| sportType | number | 运动类型：参考100种运动类型 |  |
| steps | number | 总步数 |  |
| distance | number | 总距离（米） |  |
| speed | number | 速度（m/s） |  |
| calorie | number | 卡路里（卡） |  |
| paceTime | number | 配速（min/Km） |  |
| stepFrequency | number | 步频 |  |
| heartRateLength | number | 心率数据长度 |  |
| heartRateAvg | number | 平均心率 |  |
| heartRateList | Array | 心率数据数组 |  |
| locationLength | number | gps数据长度 |  |
| locations | Array | gps数据 |  |

---

#### 5.45 同步计步睡眠：

###### request：

ts

sdk.getStepHistory({  
	year: number,  
	month: number,  
	day: number

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.StepHistory,  
    "interval":1,  
    "year":2025,  
    "month":2,  
    "day":7,  
    "dataLength":2000,  
    "stepsList":\[  
        {  
            "hour":16,  
            "minute":8,  
            "dataType":1,  
            "steps":1000,  
            "calorie":1000,  
            "distance":1000  
        }  
    \],  
    "sleepList":\[  
        {  
            "hour":16,  
            "minute":8,  
            "dataType":2,  
            "sleepStatus":1  
        }  
    \]

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| interval | number | 采样间隔 |  |
| year | number | 年 |  |
| month | number | 月 |  |
| day | number | 日 |  |
| step.hour,sleep.hour | number | 小时 |  |
| step.minute,sleep.minute | number | 分钟 |  |
| stepList | Array | 步数列表 |  |
| sleepList | Array | 睡眠列表 |  |
| step.steps | number | 步数 |  |
| step.distance | number | 距离（分米） |  |
| step.calorie | number | 卡路里（卡） |  |
| sleep.sleepStatus | number | 睡眠状态 | 1 开始入睡 2 浅睡 3 深睡 4 清醒 5 快速眼动（超过128代表小睡，需减去128） |

---

#### 5.46 同步心率记录：

###### request：

ts

sdk.getHeartRateHistory({  
	year: number,  
	month: number,  
	day: number

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.HeartRateHistory,  
    "interval":1,  
    "year":2023,  
    "month":2,  
    "day":7,  
    "dataLength":2000,  
    "heartRateList":\[  
        {  
            "hour":16,  
            "minute":8,  
            "heartRateValue":100  
        }  
    \]

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| interval | number | 采样间隔 |  |
| year | number | 年 |  |
| month | number | 月 |  |
| day | number | 日 |  |
| dataLength | number | 数据总长度 |  |
| heartRateList | Array | 心率数组 |  |
| heartRate.hour | number | 小时 |  |
| heartRate.minute | number | 分钟 |  |
| heartRate.heartRateValue | number | 心率 |  |

---

#### 5.47 同步血压数据：

###### request：

ts

sdk.getBloodPressureHistory({  
	year: number,  
	month: number,  
	day: number

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.BloodPressureHistory,  
    "interval":1,  
    "year":2023,  
    "month":2,  
    "day":7,  
    "dataLength":2000,  
    "bloodPressureList":\[  
        {  
            "hour":16,  
            "minute":8,  
            "ss":100,  
            "fz":80  
        }  
    \]

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| interval | number | 采样间隔 |  |
| year | number | 年 |  |
| month | number | 月 |  |
| day | number | 日 |  |
| dataLength | number | 数据总长度 |  |
| bloodPressureList | Array | 血压数组 |  |
| bloodPressure.hour | number | 小时 |  |
| bloodPressure.minute | number | 分钟 |  |
| bloodPressure.ss | number | 收缩压 |  |
| bloodPressure.fz | number | 舒张压 |  |

---

#### 5.48 同步血氧数据：

###### request：

ts

sdk.getBloodOxygenHistory({  
	year: number,  
	month: number,  
	day: number

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.BloodOxygenHistory,  
    "interval":1,  
    "year":2023,  
    "month":2,  
    "day":7,  
    "dataLength":2000,  
    "bloodOxygenList":\[  
        {  
            "hour":16,  
            "minute":8,  
            "bloodOxygen":100  
        }  
    \]

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| interval | number | 采样间隔 |  |
| year | number | 年 |  |
| month | number | 月 |  |
| day | number | 日 |  |
| dataLength | number | 数据总长度 |  |
| bloodOxygenList | Array | 血氧数组 |  |
| bloodOxygen.hour | number | 小时 |  |
| bloodOxygen.minute | number | 分钟 |  |
| bloodOxygen.bloodOxygen | number | 血氧 |  |

---

#### 5.49 同步压力数据：

###### request：

ts

sdk.getPressureHistory({  
	year: number,  
	month: number,  
	day: number

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.PressureHistory,  
    "interval":1,  
    "year":2023,  
    "month":2,  
    "day":7,  
    "dataLength":2000,  
    "pressureList":\[  
        {  
            "hour":16,  
            "minute":8,  
            "pressure":60  
        }  
    \]

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| interval | number | 采样间隔 |  |
| year | number | 年 |  |
| month | number | 月 |  |
| day | number | 日 |  |
| dataLength | number | 数据总长度 |  |
| pressureList | Array | 压力数组 |  |
| pressure.hour | number | 小时 |  |
| pressure.minute | number | 分钟 |  |
| pressure.pressure | number | 压力 |  |

---

#### 5.50 同步梅脱数据：

###### request：

ts

sdk.getMetHistory({  
	year: number,  
	month: number,  
	day: number

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.MetHistory,  
    "interval":1,  
    "year":2023,  
    "month":2,  
    "day":7,  
    "dataLength":1,  
    "metList":\[3\]

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| interval | number | 采样间隔 |  |
| year | number | 年 |  |
| month | number | 月 |  |
| day | number | 日 |  |
| dataLength | number | 数据总长度 |  |
| metList | Array | 梅脱数组 |  |

---

#### 5.51 同步温度数据：

###### request：

ts

sdk.getTempHistory({  
	year: number,  
	month: number,  
	day: number

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.TempHistory,  
    "interval":1,  
    "year":2023,  
    "month":2,  
    "day":7,  
    "dataLength":1,  
    "tempList":\[  
        {  
            "hour":16,  
            "minute":8,  
            "temp":365  
        }  
    \]

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| interval | number | 采样间隔 |  |
| year | number | 年 |  |
| month | number | 月 |  |
| day | number | 日 |  |
| dataLength | number | 数据总长度 |  |
| tempList | Array | 温度数组 |  |
| temp.hour | number | 小时 |  |
| temp.minute | number | 分钟 |  |
| temp.temp | number | 摄氏度 |  |

---

#### 5.52 同步MAI数据：

###### request：

ts

sdk.getMaiHistory({  
	year: number,  
	month: number,  
	day: number

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.MaiHistory,  
    "interval":1,  
    "year":2023,  
    "month":2,  
    "day":7,  
    "dataLength":1,  
    "maiList":\[50\]

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| interval | number | 采样间隔 |  |
| year | number | 年 |  |
| month | number | 月 |  |
| day | number | 日 |  |
| dataLength | number | 数据总长度 |  |
| maiList | Array | MAI数组 |  |

---

#### 5.53 获取历史数据有效日期：

###### request：

ts

sdk.getValidHistoryDates(historyType: HistoryType)

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.ValidHistoryDates,  
    "validHistoryDates":\[  
        {  
            "year":2023,  
            "month":2,  
            "day":7  
        }  
    \]

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| historyType | HistoryType | 历史数据类型 | 详情查看HistoryType枚举 |
| validHistoryDates | Array | 有效日期数组 |  |
| validHistoryDate.year | number | 年 |  |
| validHistoryDate.month | number | 月 |  |
| validHistoryDate.day | number | 日 |  |

---

#### 5.54 发送文件信息指令：(传输文件前调用，设备通过此类信息分辨表盘、UI、固件等信息)

* 5.54.1 发送表盘

###### request:

ts

sdk.sendDial({  
	dialId : number;  
	color: number;  
	align: number;  
	fileSize: number;

})

* 5.54.2 发送UI

###### request:

ts

sdk.sendUi({  
	offset: number;  
	version: string;  
	fileSize: number;

})

* 5.54.3 发送固件

###### request:

ts

sdk.sendFirmware(fileSize: number)

* 5.54.4 发送logo

###### request:

ts

sdk.sendLogo(fileSize: number)

* 5.54.5 发送gps星历

###### request:

ts

sdk.sendPgl(fileSize: number)

* 5.54.6 发送mp3

###### request:

ts

sdk.sendMp3(fileSize: number, eventIndex: number)

###### response

json

{  
	"status": 0,  
	"type": NotifyType.SendFileInfo

}

###### 字段说明：

| 字段 | 类型 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| dialId | number | 表盘id |  |
| color | number | 颜色值(rgb565) |  |
| align | number | 表盘位置 | 1：上 2：中 3：下 |
| fileSize | number | 文件大小（字节） |  |
| eventIndex | number | mp3绑定的事件索引 |  |
| offset | number | ui偏移地址 |  |
| version | number | ui版本号 |  |

---

#### 5.55 文件传输指令（需先发送文件信息指令）

是  
是  
所有分包发送完成  
发送失败  
readFile 读取文件内容  
bleFileSender.initFile 初始化分包  
SDK 发送文件信息  
收到 NotifyType.SendFileInfo 通知  
bleFileSender.sendFile 发送第一个分包  
收到 NotifyType.SendFile 通知  
bleFileSender.updateSuccessCount 更新进度  
bleFileSender.sendFile 发送下一个分包  
onSendComplete 显示“文件传输完成”  
onFailure 显示“文件发送失败”

###### request

ts

sdk.sendFile(chunkIndex: number, buffer: Uint8Array)

###### response

json

{  
	"status": 0,  
	"type": NotifyType.SendFile

}

###### 字段说明：

| 字段 | 类型 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| chunkIndex | number | 包编号 |  |
| buffer | Uint8Array | 文件数据 |  |

---

#### 5.56 切换表盘：

###### request：

ts

sdk.switchDial(dialId: number)

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.SwitchDial

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| dialId | number | 表盘ID |  |
| type | NotifyType | 返回类型 |  |

---

#### 5.57 获取表盘数据：

###### request：

ts

sdk.getDialInfo()

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.DialInfo,  
    "dialList":\[  
        {  
            "isSelected":1,  
            "id":5001,  
            "dialColor": 0,  
            "align": 1  
        }  
    \]

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| dialList | Array | 表盘数组 |  |
| dial.isSelected | number | 1 选中 ，0 未选中 |  |
| dial.id | number | 表盘id |  |
| dial.dialColor | number | 颜色值（rgb565） |  |
| dial.align | number | 位置 | 1:上 2:中 3:下 |

---

#### 5.58 同步血糖数据：

###### request：

ts

sdk.getBloodSugarHistory({  
	year: number,  
	month: number,  
	day: number

})

###### response：

json

{  
    "status": 0,  
    "type": NotifyType.BloodSugarHistory,  
    "interval":1,  
    "year":2023,  
    "month":2,  
    "day":7,  
    "dataLength":2000,  
    "bloodSugarList":\[  
        {  
            "hour":16,  
            "minute":8,  
            "bloodSugar":64  
        }  
    \]

}

###### 字段说明：

| 字段 | 属性 | 说明 |  |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| interval | number | 采样间隔 |  |
| year | number | 年 |  |
| month | number | 月 |  |
| day | number | 日 |  |
| dataLength | number | 数据总长度 |  |
| bloodSugarList | Array | 血糖数组 |  |
| bloodSugar.hour | number | 小时 |  |
| bloodSugar.minute | number | 分钟 |  |
| bloodSugar.bloodSugar | number | 血糖 |  |

---

#### 5.59 差分升级指令

##### 差分升级流程

设备BleFileSender应用程序设备BleFileSender应用程序初始化阶段发送差分升级文件头处理通知回调发送差分升级校验码发送校验码直接进入传输完成发送差分文件loop​alt\[校验全部成功\]\[校验未通过\]传输完成错误处理alt\[发生不可恢复错误\]解析差分升级文件初始化(传入文件数据)调用 sendDiffHeader() 方法发送文件头数据返回通知结果调用 notifyDiff() 解析结果准备差分升级数据onSend(ArrayBuffer) 回调 (校验码)发送校验码返回通知结果调用 notifyDiff() 解析结果onSend(ArrayBuffer) 回调 (后续数据)发送后续数据返回通知结果调用 notifyDiff() 解析结果onSendComplete() 回调调用 sendDiffComplete() 方法返回 ArrayBuffer (完成指令)发送完成指令确认升级完成onSuccess() 回调返回错误状态传递错误状态onFailure(status) 回调

* 5.59.1 发送差分升级头  
  request:  
* ts  
* sdk.sendDiffHeader(headerData: Uint8Array)  
* response:  
* json

{  
	"status": 0,  
	"type": NotifyType.Diff,  
	"data": \[0\]

* }  
* 5.59.2 发送差分升级校验码  
  request:  
* ts  
* sdk.sendDiffCheckCode(checkCode: Uint8Array)  
* response:  
* json

{  
	"status": 0,  
	"type": NotifyType.Diff,  
	"data": \[1,...\]

* }  
* 5.59.3 发送差分升级文件数据  
  request:  
* ts  
* sdk.sendDiffFile(fileData: Uint8Array)  
* response:  
* json

{  
	"status": 0,  
	"type": NotifyType.Diff,  
	"data": \[2\]

* }  
* 5.59.4 发送差分升级文件传输完成标志  
  request:  
* ts  
* sdk.sendDiffComplete()  
* response：  
* json

{  
	"status": 0,  
	"type": NotifyType.Diff,  
	"data": \[3\]

* }  
* 字段说明

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 | 0 |
| type | NotifyType | 返回类型 |  |
| data | Array | 返回数据 |  |
| data\[0\] | number | 差分升级类型 |  |
| data\[1...n\] | number | 校验码校验结果 |  |

---

#### 5.60 同步睡眠数据

###### request：

ts

sdk.getSleepHistory({  
	year: number,  
	month: number,  
	day: number

})

###### response

json

{  
    "status": 0,  
    "type": NotifyType.SleepHistory,  
    "interval":1,  
    "year":2023,  
    "month":2,  
    "day":7,  
    "dataLength":2000,  
    "sleepDataList":\[  
        {  
            "hour":16,  
            "minute":8,  
            "status":1  
        }  
    \]

}

###### 字段说明：

| 字段 | 属性 | 说明 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| interval | number | 采样间隔 |  |
| year | number | 年 |  |
| month | number | 月 |  |
| day | number | 日 |  |
| dataLength | number | 数据总长度 |  |
| sleepDataList | Array | 睡眠数据数组 |  |
| sleepData.hour | number | 小时 |  |
| sleepData.minute | number | 分钟 |  |
| sleepData.status | number | 睡眠状态 | 1 开始入睡 2 浅睡 3 深睡 4 清醒 5 快速眼动（超过128代表小睡，需减去128） |

---

#### 5.61 同步呼吸率数据

###### request：

ts

sdk.getRespirationRateHistory({  
	year: number,  
	month: number,  
	day: number

})

###### response

json

{  
    "status": 0,  
    "type": NotifyType.RespirationRateHistory,  
    "interval":1,  
    "year":2023,  
    "month":2,  
    "day":7,  
    "dataLength":2000,  
    "respirationList":\[  
        {  
            "hour":16,  
            "minute":8,  
            "respirationRate":1  
        }  
    \]

}

###### 字段说明：

| 字段 | 属性 | 说明 |  |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| interval | number | 采样间隔 |  |
| year | number | 年 |  |
| month | number | 月 |  |
| day | number | 日 |  |
| dataLength | number | 数据总长度 |  |
| respirationList | Array | 呼吸率数组 |  |
| respiration.hour | number | 小时 |  |
| respiration.minute | number | 分钟 |  |
| respiration.status | respirationRate | 呼吸率 |  |

---

#### 5.62 同步中高强度和站立次数

###### request：

ts

sdk.getExerciseHistory({  
	year: number,  
	month: number,  
	day: number

})

###### response

json

{  
    "status": 0,  
    "type": NotifyType.ExerciseHistory,  
    "interval":1,  
    "year":2023,  
    "month":2,  
    "day":7,  
    "dataLength":2000,  
    "exerciseDataList":\[  
        {  
            "hour":16,  
            "minute":8,  
            "intensity":1  
        }  
    \],  
    "standDataList":\[  
        {  
            "hour":16,  
            "minute":8,  
            "standCount":1  
        }  
    \]

}

###### 字段说明：

| 字段 | 属性 | 说明 |  |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| interval | number | 采样间隔 |  |
| year | number | 年 |  |
| month | number | 月 |  |
| day | number | 日 |  |
| dataLength | number | 数据总长度 |  |
| exerciseDataList | Array | 运动数据数组 |  |
| exerciseData.hour | number | 小时 |  |
| exerciseData.minute | number | 分钟 |  |
| exerciseData.intensity | number | 强度 |  |
| standDataList | Array | 站立次数数组 |  |
| standData.hour | number | 小时 |  |
| standData.minute | number | 分钟 |  |
| standData.standCount | number | 站立次数 |  |

---

#### 5.63 同步健康数据测量间隔和存储间隔（双向，GTS10）

* 5.63.1 获取健康数据测量间隔和存储间隔

###### request

ts

sdk.getX04HealthIntervals()

###### response

json

{  
	"status": 0,  
	"type": NotifyType.GetHealthIntervals,  
	"cmdType": 1,  
    "healthIntervalsData": \[  
    	{  
			"healthType": 1,  
            "messureInterval": 30,  
            "storeInterval": 30  
    	}  
    \]

}

* 5.63.2 设置健康数据测量间隔和存储间隔

###### request

ts

sdk.setX04HealthIntervals(healthIntervals：HealthInterval\[\])

###### no reponse

###### 字段说明

| 字段 | 属性 | 列名 | 枚举 |
| :---- | :---- | :---- | :---- |
| status | number | 状态码 |  |
| type | NotifyType | 返回类型 |  |
| cmdType | number | 指令类型 | 0：读 1：写 |
| healthIntervalsData | Array | 健康数据间隔数组 |  |
| HealthInterval.healthType | number | 健康数据类型 | 心率:01 血氧:02 温度:03 HRV:04 血糖:05 血压:06 呼吸率:07 |
| HealthInterval.messureInterval | number | 采样间隔（分钟） |  |
| HealthInterval.storeInterval | number | 存储间隔（分钟） |  |

#### 6\. 获取表盘列表

###### request

ts

sdk.getDialList(model: string)

###### response

json

\[  
	{  
        "id": 56,  
        "title": "Armor",  
        "label\_id": 1,  
        "custom\_id": 25018,  
        "pic\_url": "https://www.runmefit.cn/storage/dial/FirmwareX01Gts5Ui/Armor.png",  
        "bin\_url": "https://starmaxdial.oss-accelerate.aliyuncs.com/FirmwareX01Gts5Ui/Armor.bin"  
    },  
    {  
        "id": 1,  
        "title": "Rainbow Components",  
        "label\_id": 1,  
        "custom\_id": 1,  
        "pic\_url": "https://www.runmefit.cn/storage/20221205/rainbowcomponents.png",  
        "bin\_url": "https://www.runmefit.cn/storage/20221202/extern\_dial\_src.bin"  
    },

\]

###### 字段说明

| 字段 | 属性 | 列名 | 备注 |
| :---- | :---- | :---- | :---- |
| model | string | 批次号 | 例：X01M01T001 |
| id | number | id |  |
| title | string | 表盘名称 |  |
| label\_id | number | label\_id | 无意义 |
| custom\_id | number | 表盘id(发送给表盘用) | 1-5000代表默认表盘，5001-25000代表自定义表盘，25000以上代表市场表盘 |
| pic\_url | string | 表盘封面图片地址 |  |
| bin\_url | string | 表盘bin文件地址 |  |

