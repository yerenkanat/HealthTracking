<template>
	<view>
		<button @click="handleGetState">获取设备状态</button>
		<button @click="handleSetState">设置设备状态</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	import { useAppStore } from '../store';
import { writeBleData } from '../utils/writeBleData';
	const appStore = useAppStore()
	const sdk = starmaxSDK
	function handleGetState() {
		if(!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.getState()
		writeBleData(buffer)
	}
	function handleSetState() {
		if(!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.setState({
			timeFormat: 0,
			unitFormat: 0,
			tempFormat: 0,
			language: 0,
			backlighting: 5,
			screen: 30,
			wristUp: true
		})
		writeBleData(buffer)
	}
</script>

<style>

</style>