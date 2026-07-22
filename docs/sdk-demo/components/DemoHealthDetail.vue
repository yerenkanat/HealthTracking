<template>
	<view>
		<button @click="handleGetHealthDetail">获取设备健康数据</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	import { useAppStore } from '../store';
	import { writeBleData } from '../utils/writeBleData';
	const appStore = useAppStore();
	const sdk = starmaxSDK
	function handleGetHealthDetail() {
		if(!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.getHealthDetail();
		writeBleData(buffer);
	}
</script>

<style>

</style>