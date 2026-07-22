<template>
	<view>
		<button @click="handleGetHealthOpen">获取健康数据检测开关</button>
		<button @click="handleSetHealthOpen">设置健康数据检测开关</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	import { useAppStore } from '../store';
	import { writeBleData } from '../utils/writeBleData';
	const appStore = useAppStore();
	const sdk = starmaxSDK
	function handleGetHealthOpen() {
		if(!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.getHealthOpen();
		writeBleData(buffer);
	}
	function handleSetHealthOpen() {
		if(!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.setHealthOpen({
			heartRate: true,
			bloodOxygen: true,
			bloodPressure: false,
			pressure: false,
			temp: true,
			bloodSugar: true,
			breatheRate: true
		});
		writeBleData(buffer);
	}
</script>

<style>

</style>