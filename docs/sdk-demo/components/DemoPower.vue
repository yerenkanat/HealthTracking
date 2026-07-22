<template>
	<view>
		<button @click="handleGetPower">获取电池电量</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	import { useAppStore } from '../store';
	import { writeBleData } from '../utils/writeBleData';
	const appStore = useAppStore();
	const sdk = starmaxSDK
	function handleGetPower() {
		if(!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.getPower();
		writeBleData(buffer);
	}
</script>

<style>

</style>