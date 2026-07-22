<template>
	<view>
		<button @click="handleReset">恢复出厂设置</button>
		<button @click="blueSysPair">蓝牙系统配对</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	import { useAppStore } from '../store';
	import { writeBleData } from '../utils/writeBleData';
	const appStore = useAppStore();
	const sdk = starmaxSDK
	function blueSysPair() {
		if (!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.blueSysPair();
		writeBleData(buffer);
	}
	function handleReset() {
		if (!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		uni.showModal({
			title: '提示',
			content: '确定要恢复出厂设置吗？',
			success: (res) => {
				if (res.confirm) {
					const buffer = sdk.reset();
					writeBleData(buffer);
				}
			}
		})
	}
</script>

<style>

</style>