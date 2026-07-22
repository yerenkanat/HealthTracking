<template>
	<view>
		<button @click="setGoals">设置运动目标</button>
		<button @click="getGoals">获取运动目标</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	import { useAppStore } from '../store';
	import { writeBleData } from '../utils/writeBleData';
	const appStore = useAppStore();
	const sdk = starmaxSDK
	function setGoals() {
		if (!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.setGoals({
			heat: 65535,
			distance: 65535,
			steps: 65535
		});
		writeBleData(buffer);
	}
	function getGoals() {
		if (!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.getGoals();
		writeBleData(buffer);
	}
</script>

<style>

</style>