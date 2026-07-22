<template>
	<view>
		<button @click="handleGetVersion">获取版本信息</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	import { useAppStore } from '../store';
	import { writeBleData } from '../utils/writeBleData';
	const appStore = useAppStore();
	const sdk = starmaxSDK
	function handleGetVersion() {
		if(!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.getVersion();
		writeBleData(buffer);
	}
</script>

<style>

</style>