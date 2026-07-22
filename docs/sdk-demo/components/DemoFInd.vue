<template>
	<view>
		<button @click="handleFindPhone(true)">查找设备</button>
		<button @click="handleFindPhone(false)">停止查找设备</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	import { useAppStore } from '../store';
import { writeBleData } from '../utils/writeBleData';
	const appStore = useAppStore()
	const sdk = starmaxSDK
	function handleFindPhone(isFind: boolean) {
		if(!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.findPhone(isFind)
		writeBleData(buffer)
	}
</script>

<style>

</style>