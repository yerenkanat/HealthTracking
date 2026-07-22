<template>
	<view>
		<button @click="handlePhoneCamera(1)">拍照控制（进入拍照界面）</button>
		<button @click="handlePhoneCamera(2)">拍照控制（退出拍照界面）</button>
	</view>
</template>

<script setup lang="ts">
	import { starmaxSDK } from "../libs/StarmaxSDK";
	import { CameraControlType } from "../libs/StarmaxSDK/types";
	import { useAppStore } from "../store";
	import { writeBleData } from "../utils/writeBleData";
	const appStore = useAppStore();
	const sdk = starmaxSDK
	function handlePhoneCamera(type : CameraControlType) {
		if (!appStore.isInit)
			return uni.showToast({ title: "请先连接设备", icon: "none" });
		const buffer = sdk.cameraControl(type);
		writeBleData(buffer);
	}
</script>

<style></style>