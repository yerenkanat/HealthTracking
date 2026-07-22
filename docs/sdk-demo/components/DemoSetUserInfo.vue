<template>
	<view>
		<button @click="handleSetUserInfo">设置用户信息</button>
		<button @click="handleGetUserInfo">获取用户信息</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	import { useAppStore } from '../store';
	import { writeBleData } from '../utils/writeBleData';
	const appStore = useAppStore()
	const sdk = starmaxSDK
	function handleSetUserInfo() {
		if (!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.setUserInfo({
			sex: 0,
			age: 50,
			height: 150,
			weight: 1500
		})
		writeBleData(buffer)
	}
	function handleGetUserInfo() {
		if (!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.getUserInfo()
		writeBleData(buffer)
	}
</script>

<style>

</style>