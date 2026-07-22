<template>
	<view>
		<button @click="handlePhoneControl(CallControlType.Incoming)">来电（号码/名字）</button>
		<button @click="handlePhoneControl(CallControlType.Exit)">去电（号码）</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	import { CallControlType } from "../libs/StarmaxSDK/types";
	import { useAppStore } from '../store';
	import { writeBleData } from '../utils/writeBleData';
	const appStore = useAppStore();
	const sdk = starmaxSDK
	function handlePhoneControl(controlType: CallControlType) {
		if (!appStore.isInit) return uni.showToast({ title: '请先连接设备', icon: 'none' })
		const buffer = sdk.phoneControl({
			value: '13751121896', 
			isNumber: true,
			callControlType: controlType
		});
		writeBleData(buffer);
	}
</script>

<style>

</style>