<template>
	<view>
		<button @click="handlePair">配对</button>
		<button @click="handleGts10Pair">GTS10专用配对</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	import { writeBleData } from '../utils/writeBleData';
	import { useAppStore } from '../store';
	const appStore = useAppStore()
	const sdk = starmaxSDK
	function handlePair() {
		if (!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.pair()
		writeBleData(buffer)
	}
	function handleGts10Pair() {
		if (!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.pairGts10(false)
		writeBleData(buffer)
	}
</script>

<style>

</style>