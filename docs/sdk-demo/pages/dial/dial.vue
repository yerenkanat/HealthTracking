<template>
	<button @click="getDials">获取表盘</button>
</template>

<script setup lang="ts">
import { starmaxSDK } from "../../libs/StarmaxSDK";
import { useNotify } from "../../hooks/useNotify";
import { writeBleData } from "../../utils/writeBleData";
import { useAppStore } from "../../store";
import { NotifyType } from "../../libs/StarmaxSDK/types";
const sdk = starmaxSDK

const {
	notifySuccessCb
} = useNotify()
const appStore = useAppStore();
function checkIsInit() {
  if (!appStore.isInit)
    return uni.showToast({ title: "请先连接设备", icon: "none" });
}
notifySuccessCb((res) => {
	if (res.type == NotifyType.Version) {
		const model = res.model
		sdk.getDialList(model).then((res) => {
			console.log(res);
		});
	}
})
function getDials() {
	checkIsInit();
	const buffer = sdk.getVersion()
	writeBleData(buffer)
}
</script>

<style>
</style>