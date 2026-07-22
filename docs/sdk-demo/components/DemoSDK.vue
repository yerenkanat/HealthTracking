<template>
  <view>
    <button @click="handleSetPPG">设置PPG检测开关</button>
    <button @click="handleSetBt">设置bt蓝牙连接</button>
    <button @click="handleGetBt">获取bt蓝牙连接</button>
    <button @click="handleClearLogo">清除logo</button>
    <button @click="handleSetHeartRateAlarm">设置心率报警阈值</button>
    <button @click="handleSetDisplayMode">设置进入退出演示模式</button>
    <button @click="handleSetShipMode">设置进入退出船运模式</button>
    <button @click="handleSetDateFormat">设置日期格式</button>
    <button @click="handleUnpair">解绑</button>
    <button @click="handleGetMessagePushOpen">获取消息推送开关</button>
    <button @click="handleSetMessagePushOpen">设置消息推送开关</button>
    <button @click="handleSetHeartRateControl">设置心率检测间隔</button>
    <button @click="handleGetHeartRateControl">获取心率检测间隔</button>
    <button @click="handleGetContacts">获取常用联系人</button>
    <button @click="handleSetContacts">设置常用联系人</button>
    <button @click="handleGetSos">获取紧急联系人</button>
    <button @click="handleSetSos">设置紧急联系人</button>
    <button @click="handleGetNotDisturb">获取勿扰</button>
    <button @click="handleSetNotDisturb">设置勿扰</button>
    <button @click="handleGetClocks">获取闹钟</button>
    <button @click="handleSetClocks">设置闹钟</button>
    <button @click="handleGetLongSit">获取久坐提醒</button>
    <button @click="handleSetLongSit">设置久坐提醒</button>
    <button @click="handleGetDrinkWater">获取喝水提醒</button>
    <button @click="handleSetDrinkWater">设置喝水提醒</button>
    <button @click="handleSendMessage">推送消息</button>
    <button @click="handleSetWeather">设置天气</button>
    <button @click="handleMusicControl">控制音乐</button>
    <button @click="handleGetEventReminder">获取事件提醒</button>
    <button @click="handleSetEventReminder">设置事件提醒</button>
    <button @click="handleGetSportMode">获取设备运动显示列表</button>
    <button @click="handleSetSportMode">设置设备运动显示列表</button>
    <button @click="handleSetWeatherSeven">设置当天及未来7天天气</button>
    <button @click="handleGetApps">获取推送应用列表</button>
    <button @click="handleSetApps">设置推送应用列表</button>
    <button @click="handleGetWorldClock">获取世界时钟</button>
    <button @click="handleSetWorldClock">设置世界时钟</button>
    <button @click="handleGetDialInfo">获取表盘信息</button>
    <button @click="handleSwitchDial">切换当前表盘</button>
    <button @click="handleGetPassword">获取密码</button>
    <button @click="handleSetPassword">设置密码</button>
    <button @click="handleGetFemaleHealth">获取女性健康</button>
    <button @click="handleSetFemaleHealth">设置女性健康</button>
    <button @click="handlehealthMeasurements">健康测量指令</button>
    <button @click="handleGetSummerWorldClock">获取世界时钟夏令时</button>
    <button @click="handleSetSummerWorldClock">设置世界时钟夏令时</button>
    <button @click="handleGetSupportLanguages">获取设备语言列表</button>
    <button @click="handleGetSleepClock">获取睡眠提醒</button>
    <button @click="handleSetSleepClock">设置睡眠提醒</button>
  </view>
</template>

<script setup lang="ts">
import { useAppStore } from "../store";
import { starmaxSDK } from "../libs/StarmaxSDK/index.js";
// import { starmaxSDK } from "../utils";
import {
  CalibrationValue,
  HealthMeasureType,
  HistoryType,
  MessageType,
  NotifyType,
  SummerWorldClock,
  WeatherDay,
  WeatherDaySeven,
  sportSyncToDeviceRequest,
	EventReminder
} from "../libs/StarmaxSDK/types";
import { writeBleData } from "../utils/writeBleData";
const sdk = starmaxSDK;
const appStore = useAppStore();
function checkIsInit() {
  if (!appStore.isInit)
    return uni.showToast({ title: "请先连接设备", icon: "none" });
}
function handleSetPPG() {
  checkIsInit();
  const buffer = sdk.setPPGOpen(false);
  writeBleData(buffer);
}
function handleSetMessagePushOpen() {
  checkIsInit();
  const buffer = sdk.setMessagePushOpen({
    mainSwitch: true,
    switches: {
      phone: false,
      twitter: true,
      groupme: true,
    },
  });
  writeBleData(buffer);
}
function handleGetMessagePushOpen() {
  checkIsInit();
  const buffer = sdk.getMessagePushOpen();
  writeBleData(buffer);
}
function handleSetBt() {
  checkIsInit();
  const buffer = sdk.setBtStatus(false);
  writeBleData(buffer);
}
function handleGetBt() {
  checkIsInit();
  const buffer = sdk.getBtStatus();
  writeBleData(buffer);
}
function handleClearLogo() {
  checkIsInit();
  const buffer = sdk.clearLogo();
  writeBleData(buffer);
}
function handleSetHeartRateAlarm() {
  checkIsInit();
  const buffer = sdk.setHeartRateAlarmThreshold(true, 99);
  writeBleData(buffer);
}
function handleSetDisplayMode() {
  checkIsInit();
  const buffer = sdk.setDisplayMode(false);
  writeBleData(buffer);
}
function handleSetShipMode() {
  checkIsInit();
  const buffer = sdk.setShipMode(true);
  writeBleData(buffer);
}
function handleSetDateFormat() {
  checkIsInit();
  const buffer = sdk.setDateFormat(true);
  writeBleData(buffer);
}
function handleUnpair() {
  checkIsInit();
  uni.showModal({
    title: "提示",
    content: "确定要解绑吗？",
    success: (res) => {
      if (res.confirm) {
        const buffer = sdk.unpair(0);
        writeBleData(buffer);
      }
    },
  });
}
function handleSetHeartRateControl() {
  checkIsInit();
  const buffer = sdk.setHeartRateControl({
    startHour: 0,
    startMinute: 0,
    endHour: 23,
    endMinute: 59,
    period: 1,
    alarmThreshold: 70,
  });
  writeBleData(buffer);
}
function handleGetHeartRateControl() {
  checkIsInit();
  const buffer = sdk.getHeartRateControl();
  writeBleData(buffer);
}
function handleGetContacts() {
  checkIsInit();
  const buffer = sdk.getContacts();
  writeBleData(buffer);
}
function handleSetContacts() {
  checkIsInit();
  const buffer = sdk.setContacts([
    { name: "大声的", number: "45454891616" },
    { name: "魑魅魍魉", number: "231211121" },
    { name: "理论", number: "131165466456321" },
  ]);
  writeBleData(buffer);
}
function handleGetSos() {
  checkIsInit();
  const buffer = sdk.getSos();
  writeBleData(buffer);
}
function handleSetSos() {
  checkIsInit();
  const buffer = sdk.setSos([
    { name: "急救电话", number: "120" },
  ]);
  writeBleData(buffer);
}
function handleGetNotDisturb() {
  checkIsInit();
  const buffer = sdk.getNotDisturb();
  writeBleData(buffer);
}
function handleSetNotDisturb() {
  checkIsInit();
  const buffer = sdk.setNotDisturb({
    startHour: 14,
    startMinute: 0,
    endHour: 14,
    endMinute: 59,
    allDayOnOff: false,
    onOff: true,
  });
  writeBleData(buffer);
}
function handleGetClocks() {
  checkIsInit();
  const buffer = sdk.getClocks();
  writeBleData(buffer);
}
function handleSetClocks() {
  checkIsInit();
  const buffer = sdk.setClocks([
    {
      hour: 18,
      minute: 59,
      onOff: false,
      repeats: [0, 1, 1, 1, 1, 1, 1],
      clockType: 0,
    },
  ]);
  writeBleData(buffer);
}
function handleGetLongSit() {
  checkIsInit();
  const buffer = sdk.getLongSit();
  writeBleData(buffer);
}
function handleSetLongSit() {
  checkIsInit();
  const buffer = sdk.setLongSit({
    onOff: true,
    startHour: 15,
    startMinute: 30,
    endHour: 23,
    endMinute: 50,
    interval: 30,
  });
  writeBleData(buffer);
}
function handleGetDrinkWater() {
  checkIsInit();
  const buffer = sdk.getDrinkWater();
  writeBleData(buffer);
}
function handleSetDrinkWater() {
  checkIsInit();
  const buffer = sdk.setDrinkWater({
    onOff: true,
    startHour: 15,
    startMinute: 30,
    endHour: 23,
    endMinute: 50,
    interval: 30,
  });
  writeBleData(buffer);
}
function handleSendMessage() {
  checkIsInit();
  const buffer = sdk.sendMessage({
    content: "test123",
    title: "测试标题321",
    messageType: MessageType.Telegram,
  });
  writeBleData(buffer);
}
function handleSetWeather() {
  checkIsInit();
  const weatherDays: Array<WeatherDay> = [
    {
      temp: 30,
      maxTemp: 40,
      minTemp: 20,
      windSpeed: 11,
      dampness: 50,
      seeing: 99,
      uv: 66,
      airQuality: 2,
      type: 20,
    },
    {
      temp: 32,
      maxTemp: 42,
      minTemp: 22,
      windSpeed: 13,
      dampness: 52,
      seeing: 99,
      uv: 68,
      airQuality: 1,
      type: 2,
    },
    {
      temp: 34,
      maxTemp: 44,
      minTemp: 24,
      windSpeed: 15,
      dampness: 54,
      seeing: 95,
      uv: 70,
      airQuality: 3,
      type: 21,
    },
    {
      temp: 36,
      maxTemp: 46,
      minTemp: 24,
      windSpeed: 15,
      dampness: 55,
      seeing: 64,
      uv: 42,
      airQuality: 2,
      type: 14,
    },
  ];
  const buffer = sdk.setWeather(weatherDays);
  writeBleData(buffer);
}
function handleMusicControl() {
  checkIsInit();
  const buffer = sdk.musicControl({
    playState: 1,
    volPercent: 60,
    ratePercent: 50,
    musicTitle: "测试123-The Beatles",
    lyric: "hey jude\ndon't make it bad",
  });
  writeBleData(buffer);
}
function handleGetEventReminder() {
  checkIsInit();
  const buffer = sdk.getEventReminder();
  writeBleData(buffer);
}
function handleSetEventReminder() {
  checkIsInit();
  const date = new Date();
  const reminders: Array<EventReminder> = [
    {
      year: date.getFullYear(),
      month: date.getMonth() + 1,
      day: date.getDate(),
      hour: date.getHours(),
      minute: date.getMinutes() + 2,
      content: "测试提醒-不传",
      remindType: 2,
      repeatType: 3,
      repeats: [1, 1, 1, 1, 1, 1, 1],
    },
		{
		  year: date.getFullYear(),
		  month: date.getMonth() + 1,
		  day: date.getDate(),
		  hour: date.getHours(),
		  minute: date.getMinutes() + 1,
		  content: "测试提醒-传8",
		  remindType: 2,
		  repeatType: 1,
		  repeats: [1, 1, 1, 1, 1, 1, 1],
			reminderIndex: 8,
		},
		{
		  year: date.getFullYear(),
		  month: date.getMonth() + 1,
		  day: date.getDate(),
		  hour: date.getHours(),
		  minute: date.getMinutes() + 3,
		  content: "测试提醒-mp3",
		  remindType: 2,
		  repeatType: 1,
		  repeats: [1, 0, 0, 0, 0, 0, 1],
		  reminderIndex: 3,
		}
  ];
  const buffer = sdk.setEventReminder(reminders);
  writeBleData(buffer);
}
function handleGetSportMode() {
  checkIsInit();
  const buffer = sdk.getSportModes();
  writeBleData(buffer);
}
function handleSetSportMode() {
  checkIsInit();
  const buffer = sdk.setSportModes([3, 1, 2, 5]);
  writeBleData(buffer);
}
function handleSetWeatherSeven() {
  checkIsInit();
  const weatherDaysSeven: Array<WeatherDaySeven> = [
    {
      temp: 25,
      maxTemp: 30,
      minTemp: 20,
      windSpeed: 11,
      dampness: 50,
      seeing: 99,
      uv: 66,
      airQuality: 2,
      type: 1,
      sunriseHour: 6,
      sunriseMinute: 30,
      sunsetHour: 18,
      sunsetMinute: 28,
      moonriseHour: 19,
      moonriseMinute: 0,
      moonsetHour: 23,
      moonsetMinute: 28,
    },
    {
      temp: 25,
      maxTemp: 30,
      minTemp: 20,
      windSpeed: 11,
      dampness: 50,
      seeing: 99,
      uv: 66,
      airQuality: 2,
      type: 1,
      sunriseHour: 6,
      sunriseMinute: 30,
      sunsetHour: 18,
      sunsetMinute: 28,
      moonriseHour: 19,
      moonriseMinute: 0,
      moonsetHour: 23,
      moonsetMinute: 28,
    },
    {
      temp: 25,
      maxTemp: 30,
      minTemp: 20,
      windSpeed: 11,
      dampness: 50,
      seeing: 99,
      uv: 66,
      airQuality: 2,
      type: 1,
      sunriseHour: 6,
      sunriseMinute: 30,
      sunsetHour: 18,
      sunsetMinute: 28,
      moonriseHour: 19,
      moonriseMinute: 0,
      moonsetHour: 23,
      moonsetMinute: 28,
    },
    {
      temp: 25,
      maxTemp: 30,
      minTemp: 20,
      windSpeed: 11,
      dampness: 50,
      seeing: 99,
      uv: 66,
      airQuality: 2,
      type: 1,
      sunriseHour: 6,
      sunriseMinute: 30,
      sunsetHour: 18,
      sunsetMinute: 28,
      moonriseHour: 19,
      moonriseMinute: 0,
      moonsetHour: 23,
      moonsetMinute: 28,
    },
    {
      temp: 25,
      maxTemp: 30,
      minTemp: 20,
      windSpeed: 11,
      dampness: 50,
      seeing: 99,
      uv: 66,
      airQuality: 2,
      type: 1,
      sunriseHour: 6,
      sunriseMinute: 30,
      sunsetHour: 18,
      sunsetMinute: 28,
      moonriseHour: 19,
      moonriseMinute: 0,
      moonsetHour: 23,
      moonsetMinute: 28,
    },
    {
      temp: 25,
      maxTemp: 30,
      minTemp: 20,
      windSpeed: 11,
      dampness: 50,
      seeing: 99,
      uv: 66,
      airQuality: 2,
      type: 1,
      sunriseHour: 6,
      sunriseMinute: 30,
      sunsetHour: 18,
      sunsetMinute: 28,
      moonriseHour: 19,
      moonriseMinute: 0,
      moonsetHour: 23,
      moonsetMinute: 28,
    },
    {
      temp: 25,
      maxTemp: 30,
      minTemp: 20,
      windSpeed: 11,
      dampness: 50,
      seeing: 99,
      uv: 66,
      airQuality: 2,
      type: 0,
      sunriseHour: 6,
      sunriseMinute: 30,
      sunsetHour: 18,
      sunsetMinute: 28,
      moonriseHour: 19,
      moonriseMinute: 0,
      moonsetHour: 23,
      moonsetMinute: 28,
    },
    {
      temp: 25,
      maxTemp: 30,
      minTemp: 20,
      windSpeed: 11,
      dampness: 50,
      seeing: 99,
      uv: 66,
      airQuality: 2,
      type: 0,
      sunriseHour: 6,
      sunriseMinute: 30,
      sunsetHour: 18,
      sunsetMinute: 28,
      moonriseHour: 19,
      moonriseMinute: 0,
      moonsetHour: 23,
      moonsetMinute: 28,
    },
  ];
  const buffer = sdk.setWeatherSeven({
    cityName: "东京",
    weatherDays: weatherDaysSeven,
  });
  writeBleData(buffer);
}
function handleGetSleepClock() {
  checkIsInit();
  const buffer = sdk.getSleepClock();
  writeBleData(buffer);
}
function handleSetSleepClock() {
  checkIsInit();
  const buffer = sdk.setSleepClock({
    fallAsleepHour: 23,
    fallAsleepMinute: 0,
    fallAsleepOnOff: true,
    getUpHour: 6,
    getUpMinute: 0,
    getUpOnOff: true,
    onOff: false,
    repeats: [1, 1, 1, 1, 1, 0, 0],
    reminderAdvanceMinute: 60,
  });
  writeBleData(buffer);
}
function handleGetApps() {
  checkIsInit();
  const buffer = sdk.getApps();
  writeBleData(buffer);
}
function handleSetApps() {
  checkIsInit();
  const buffer = sdk.setApps([1, 2, 3, 4, 8, 9]);
  writeBleData(buffer);
}
function handleGetWorldClock() {
  checkIsInit();
  const buffer = sdk.getWorldClocks();
  writeBleData(buffer);
}
function handleSetWorldClock() {
  checkIsInit();
  const buffer = sdk.setWorldClocks([1, 2, 3]);
  writeBleData(buffer);
}
function handleGetDialInfo() {
  checkIsInit();
  const buffer = sdk.getDialInfo();
  writeBleData(buffer);
}
function handleSwitchDial() {
  checkIsInit();
  const buffer = sdk.switchDial(1);
  writeBleData(buffer);
}
function handleGetPassword() {
  checkIsInit();
  const buffer = sdk.getPassword();
  writeBleData(buffer);
}
function handleSetPassword() {
  checkIsInit();
  const buffer = sdk.setPassword({
    isOpen: true,
    password: "998998",
  });
  writeBleData(buffer);
}
function handleGetFemaleHealth() {
  checkIsInit();
  const buffer = sdk.getFemaleHealth();
  writeBleData(buffer);
}
function handleSetFemaleHealth() {
  checkIsInit();
  const buffer = sdk.setFemaleHealth({
    cycleDays: 2,
    numberOfDays: 30,
    lastPeriodYear: 2025,
    lastPeriodMonth: 3,
    lastPeriodDay: 28,
    remindOnOff: true,
  });
  writeBleData(buffer);
}
function handlehealthMeasurements() {
  checkIsInit();
  const buffer = sdk.healthMeasurements({
    healthType: HealthMeasureType.Pressure,
    onOff: true,
  });
  writeBleData(buffer);
}
function handleGetSummerWorldClock() {
  checkIsInit();
  const buffer = sdk.getSummerWorldClock();
  writeBleData(buffer);
}
function handleSetSummerWorldClock() {
  checkIsInit();
  const clocks: Array<SummerWorldClock> = [
    {
      cityId: 5,
      startMonth: 1,
      startWeek: 2,
      endMonth: 12,
      endWeek: 1,
      timeOffset: -120,
    },
  ];
  const buffer = sdk.setSummerWorldClock(clocks);
  writeBleData(buffer);
}

function handleGetSupportLanguages() {
  checkIsInit();
  const buffer = sdk.getSupportLanguages();
  writeBleData(buffer);
}
</script>

<style></style>
