<template>
	<view>
		<button @click="handleCloseDevice">设备关机</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	const sdk = starmaxSDK
	import { useAppStore } from '../store';
import { writeBleData } from '../utils/writeBleData';
	const appStore = useAppStore()
	function handleCloseDevice() {
		if (!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		uni.showModal({
			title: '提示',
			content: '确定要关闭设备吗？',
			success: (res) => {
				if (res.confirm) {
					const buffer = sdk.closeDevice()
					writeBleData(buffer)
				}
			}
		})
	}
</script>

<style>

</style>