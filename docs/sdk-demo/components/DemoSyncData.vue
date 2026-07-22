<template>
	<view>
		<view class="spliter">
			<view class="spliter-label">
				同步指令
			</view>
		</view>
		<button @click="handleGetSportHistory">同步运动数据</button>
		<button @click="handleGetStepHistory">同步计步数据</button>
		<button @click="handleGetHeartRateHistory">同步心率数据</button>
		<button @click="handleGetBloodPressureHistory">同步血压数据</button>
		<button @click="handleGetBloodOxygenHistory">同步血氧数据</button>
		<button @click="handleGetPressureHistory">同步压力数据</button>
		<button @click="handleGetMetHistory">同步梅脱数据</button>
		<button @click="handleGetTempHistory">同步温度数据</button>
		<button @click="handleGetMaiHistory">同步Mai数据</button>
		<button @click="handleGetBloodSugarHistory">同步血糖数据</button>
		<button @click="handleGetSleepHistory">同步睡眠数据</button>
		<button @click="handleGetRepirationRateHistory">同步呼吸率数据</button>
		<button @click="handleGetExerciseHistory">同步中高强度和站立次数</button>
		<button @click="handleGetValidHistoryDates">获取数据有效日期</button>
		<button @click="handleSportSyncToDevice">同步运动</button>
		<button @click="handleGetX04HealthIntervals">获取X04健康间隔</button>
		<button @click="handleSetX04HealthIntervals">设置X04健康间隔</button>
	</view>
</template>

<script setup lang="ts">
	import { writeBleData } from "../utils/writeBleData";
	import { useAppStore } from "../store";
	import { starmaxSDK } from "../libs/StarmaxSDK/index";
	
	import { HealthInterval, HealthIntervalType, HistoryType, sportSyncToDeviceRequest } from "../libs/StarmaxSDK/types";
	const sdk = starmaxSDK
	const appStore = useAppStore();
	const date = new Date()
	const year = date.getFullYear()
	const month = date.getMonth() + 1
	const day = date.getDate()
	function checkIsInit() {
		if (!appStore.isInit)
			return uni.showToast({ title: "请先连接设备", icon: "none" });
	}
	function handleGetSportHistory() {
		checkIsInit();
		const buffer = sdk.getSportHistory(false);
		writeBleData(buffer);
	}
	function handleGetStepHistory() {
		checkIsInit()
		const buffer = sdk.getStepHistory({
			year,
			month,
			day
		})
		writeBleData(buffer)
	}
	function handleGetHeartRateHistory() {
		checkIsInit()
		const buffer = sdk.getHeartRateHistory({
			year,
			month,
			day
		})
		writeBleData(buffer)
	}
	function handleGetBloodPressureHistory() {
		checkIsInit()
		const buffer = sdk.getBloodPressureHistory({
			year,
			month,
			day
		})
		writeBleData(buffer)
	}
	function handleGetBloodOxygenHistory() {
		checkIsInit()
		const buffer = sdk.getBloodOxygenHistory({
			year,
			month,
			day
		})
		writeBleData(buffer)
	}
	function handleGetPressureHistory() {
		checkIsInit()
		const buffer = sdk.getPressureHistory({
			year,
			month,
			day
		})
		writeBleData(buffer)
	}
	function handleGetMetHistory() {
		checkIsInit()
		const buffer = sdk.getMetHistory({
			year,
			month,
			day
		})
		writeBleData(buffer)
	}
	function handleGetTempHistory() {
		checkIsInit()
		const buffer = sdk.getTempHistory({
			year,
			month,
			day
		})
		writeBleData(buffer)
	}
	function handleGetMaiHistory() {
		checkIsInit()
		const buffer = sdk.getMaiHistory({
			year,
			month,
			day
		})
		writeBleData(buffer)
	}
	function handleGetSleepHistory() {
		checkIsInit()
		const buffer = sdk.getSleepHistory({
			year,
			month,
			day
		})
		writeBleData(buffer)
	}
	function handleGetBloodSugarHistory() {
		checkIsInit()
		const buffer = sdk.getBloodSugarHistory({
			year,
			month,
			day
		})
		writeBleData(buffer)
	}
	function handleGetExerciseHistory() {
		checkIsInit()
		const buffer = sdk.getExerciseHistory({
			year,
			month,
			day
		})
		writeBleData(buffer)
	}
	function handleGetRepirationRateHistory() {
		checkIsInit()
		const buffer = sdk.getRespirationRateHistory({
			year,
			month,
			day
		})
		writeBleData(buffer)
	}
	function handleGetValidHistoryDates() {
		checkIsInit()
		const buffer = sdk.getValidHistoryDates(HistoryType.Step)
		writeBleData(buffer)
	}
	function handleSportSyncToDevice() {
		checkIsInit();
		const obj : sportSyncToDeviceRequest = {
			sportType: 3,
			sportStatus: 4,
			sportDistance: 2000,
			speed: 200,
			locationList: [
				{
					longitude: 116.397128,
					latitude: 39.916527,
				},
			],
		};
		const buffer = sdk.sportSyncToDevice(obj);
		writeBleData(buffer);
	}
	function handleGetX04HealthIntervals() {
		checkIsInit()
		const buffer = sdk.getX04HealthIntervals()
		writeBleData(buffer)
	}
	function handleSetX04HealthIntervals() {
		checkIsInit()
		const healthIntervals:HealthInterval[] = [
			{
				healthType: HealthIntervalType.HeartRate,
				measureInterval: 10,
				storeInterval: 10
			},
			{
				healthType: HealthIntervalType.BloodOxygen,
				measureInterval: 10,
				storeInterval: 10
			},
		]
		const buffer = sdk.setX04HealthIntervals(healthIntervals)
		writeBleData(buffer)
	}
</script>

<style>

</style>