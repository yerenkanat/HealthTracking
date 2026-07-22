<template>
	<view>
		<button @click="handleSetTimeOffset">设置单独时区</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	import { useAppStore } from '../store';
import { writeBleData } from '../utils/writeBleData';
	const appStore = useAppStore()
	const sdk = starmaxSDK
	function handleSetTimeOffset() {
		if(!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.setTimeOffset(-300)
		writeBleData(buffer)
	}
</script>

<style>

</style>