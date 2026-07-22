<template>
	<view>
		<button @click="handleSetTime">设置时间</button>
		<button @click="handleGetTime">获取时间</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	import { useAppStore } from '../store';
import { writeBleData } from '../utils/writeBleData';
	const appStore = useAppStore()
	const sdk = starmaxSDK
	function handleSetTime() {
		if(!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const date = new Date()
		const buffer = sdk.setTime(date)
		writeBleData(buffer)
	}
	function handleGetTime() {
		if(!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.getTime()
		writeBleData(buffer)
	}
</script>

<style>

</style>