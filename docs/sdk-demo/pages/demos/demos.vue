<template>
	<view class="demo-container">
		<view class="status-section">
			<view class="status-item">
				<text class="label">sdk示例</text>
			</view>
		</view>
		<DemoPair />
		<DemoState />
		<DemoFind />
		<DemoCamera />
		<DemoPower />
		<DemoGoals />
		<DemoGetVersion />
		<DemoSetTime />
		<DemoHealthDetail />
		<DemoCloseDevice />
		<DemoReset />
		<DemoSetUserInfo />
		<DemoPhoneControl />
		<DemoSetHealthOpen />
		<DemoSetTimeOffset />
		<DemoSDK />
		<DemoSyncData />
	</view>
</template>

<script setup>
	import {
		ref,
		onMounted,
		onUnmounted
	} from 'vue';
	import DemoSDK from '../../components/DemoSDK.vue';
	import DemoSetTimeOffset from '../../components/DemoSetTimeOffset.vue';
	import DemoSetHealthOpen from '../../components/DemoSetHealthOpen.vue';
	import DemoSetUserInfo from '../../components/DemoSetUserInfo.vue';
	import DemoHealthDetail from '../../components/DemoHealthDetail.vue';
	import DemoPair from '../../components/DemoPair.vue';
	import DemoSetTime from '../../components/DemoSetTime.vue';
	import DemoState from '../../components/DemoState.vue';
	import DemoReset from '../../components/DemoReset.vue';
	import DemoFind from '../../components/DemoFind.vue';
	import DemoGoals from '../../components/DemoGoals.vue';
	import DemoCamera from '../../components/DemoCamera.vue';
	import DemoPower from '../../components/DemoPower.vue';
	import DemoCloseDevice from '../../components/DemoCloseDevice.vue';
	import DemoGetVersion from '../../components/DemoGetVersion.vue';
	import DemoPhoneControl from '../../components/DemoPhoneControl.vue';
	import DemoSyncData from '../../components/DemoSyncData.vue';
	import { useNotify } from "../../hooks/useNotify";
	import { eventBus } from '../../utils/eventBus';
	const {
		notifySuccessCb
	} = useNotify()
	notifySuccessCb((res) => {
		console.log('接收到数据' + '--------------',res);
	})
</script>

<style scoped>
	.demo-container {
		padding: 20px;
		padding-bottom: 50rpx;
	}

	.status-section {
		margin-bottom: 20px;
		padding: 15px;
		border-radius: 8px;
		background-color: #f8f8f8;
	}

	.status-item {
		display: flex;
		align-items: center;
	}
</style>