<template>
	<view class="container">
		<button @click="sendFirmware">选择聊天文件发送固件</button>
		<button @click="sendLogo">选择聊天文件发送开机logo</button>
		<button @click="sendUi">选择聊天文件发送UI</button>
		<button @click="sendDial">选择聊天文件发送表盘</button>
		<button @click="getEventReminder">获取事件提醒</button>
		<button @click="showEventSelector">选择事件提醒</button>
		<view class="progress-container">
			<view class="progress-info">
				<text>传输进度：</text>
				<text>{{ progressPercentage }}%</text>
			</view>
			<view class="progress-bar">
				<view class="progress-inner" :style="{ width: progressPercentage + '%' }"></view>
			</view>
		</view>
		<view v-show="selectReminder.reminderIndex != undefined">
			当前选择的事件: {{ selectReminder.content }} | index: {{ selectReminder.reminderIndex }}
		</view>
		<EventSelector :show="showSelector" :events="eventReminderData" @close="showSelector = false"
			@select="onEventSelect" />
	</view>
</template>

<script setup lang="ts">
import {
	onMounted,
	onUnmounted,
	computed,
	ref
} from "vue";
import { starmaxSDK, bleFileSender } from "../../libs/StarmaxSDK/";
import { useAppStore } from "../../store";
import { writeBleData } from "../../utils/writeBleData";
import { NotifyType } from "../../libs/StarmaxSDK/types";
import { eventBus } from "../../utils/eventBus";
import { useNotify } from "../../hooks/useNotify";
import { splitArrayBuffer } from "../../libs/StarmaxSDK/utils";
import EventSelector from "../../components/EventSelector.vue";
import { EventReminder } from "../../libs/StarmaxSDK/types";

const sdk = starmaxSDK
const appStore = useAppStore()
const filePath = '/static/3_colourful_lines.bin'
let progressPercentage = ref(0)
let fileSize = ref(0)
const eventReminderData = ref<EventReminder[]>([])
const selectReminder = ref<EventReminder>({} as EventReminder)
const showSelector = ref(false)

const {
	notifySuccessCb
} = useNotify()

notifySuccessCb((res) => {
	if (res.type == NotifyType.SendFileInfo) {
		setTimeout(() => {
			bleFileSender.sendFile()
		}, 200)
	}
	if (res.type == NotifyType.SendFile) {
		bleFileSender.updateSuccessCount()
		bleFileSender.sendFile()
	}
	if (res.type == NotifyType.GetEventReminder) {
		uni.showToast({
			icon: 'success',
			title: `获取到${res.eventReminders.length}条提醒`
		})
		eventReminderData.value = res.eventReminders
	}
})
// 文件发送监听器
const fileSenderListener = {
	onSuccess: () => {
		console.log('文件发送成功');
	},
	onFailure: (status: number) => {
		console.log('文件发送失败:', status);
		uni.showToast({
			title: '文件发送失败',
			icon: 'error'
		});
	},
	onProgress: (progress: number) => {
		progressPercentage.value = progress;
	},
	onSend: (buffer: ArrayBuffer) => {
		writeBleData(buffer)
	},
	onSendComplete: () => {
		uni.showToast({
			title: '文件传输完成',
			icon: 'success'
		});
	},
};
function getEventReminder() {
	checkInit()
	const buffer = sdk.getEventReminder()
	writeBleData(buffer)
}
function checkInit() {
	if (!appStore.isInit)
		return uni.showToast({
			title: "请先连接设备",
			icon: "none"
		});
}
async function sendLogo() {
	await initFile()
	const buffer = sdk.sendLogo(fileSize.value)
	writeBleData(buffer)
}
async function sendUi() {
	await initFile()
	const buffer = sdk.sendUi({
		offset: 20,
		version: "1.1.0",
		fileSize: 20000
	})
	writeBleData(buffer)
}
async function sendFirmware() {
	await initFile()
	const buffer = sdk.sendFirmware(fileSize.value)
	writeBleData(buffer)
}
async function sendDial() {
	await initFile()
	const buffer = sdk.sendDial({
		dialId: 25003,
		color: 0,
		align: 1,
		fileSize: fileSize.value
	})
	writeBleData(buffer)
}
function initFile() {
	return new Promise(async resolve => {
		const fileBuffer = await readFile(filePath) as ArrayBuffer
		bleFileSender.initFile(fileBuffer, fileSenderListener)
		resolve(1)
		// wx.chooseMessageFile({
		// 	count: 1,
		// 	type: 'file',
		// 	async success(res) {
		// 		const fileBuffer = await readFile(res.tempFiles[0].path) as ArrayBuffer
		// 		bleFileSender.initFile(fileBuffer, fileSenderListener)
		// 		resolve(1)
		// 	}
		// })
	})
}
async function readFile(filePath: string) {
	return new Promise(async resolve => {
		const res: any = await getFileInfo(filePath)
		const fileBuffer = res.arrayBuffer;
		fileSize.value = res.size
		resolve(fileBuffer)
	})
}

// 读取文件获得arrayBuffer（小程序用）
function getFileInfoWx(filePath: string) {
	return new Promise((resolve, reject) => {
		let fileManager = uni.getFileSystemManager();
		fileManager.readFile({
			filePath,
			success: (res) => {
				let arrayBuffer = res.data as ArrayBuffer;
				resolve({
					size: arrayBuffer.byteLength, // 字节长度
					arrayBuffer
				});
			},
			fail: (err) => {
				console.log('读取文件失败：', err);
				reject(err);
			}
		})
	})
}

// 读取文件获得arrayBuffer（app用）
const getFileInfo = (filePath: string) => {
	return new Promise((resolve, reject) => {
		plus.io.requestFileSystem(plus.io.PRIVATE_WWW, (fs) => {
			fs.root.getFile(filePath, {
				create: false
			}, (fileEntry) => {
				fileEntry.file((file) => {
					console.log('file：', file);
					const fileReader = new plus.io.FileReader();
					fileReader.readAsDataURL(file);
					fileReader.onload = (evt: any) => {
						const base64 = evt.target.result.split(',')[1]
						const arrayBuffer = uni.base64ToArrayBuffer(base64)
						resolve({
							size: file.size,
							arrayBuffer
						});
					}
					fileReader.onerror = (err) => {
						console.log('文件读取失败');
						reject(err);
					}
				})
			}, (error) => {
				console.log('读取文件报错：', error);
				reject(error);
			})
		})
	})
}

function showEventSelector() {
	if (eventReminderData.value.length === 0) {
		uni.showToast({
			title: '请先获取事件提醒列表',
			icon: 'none'
		});
		return;
	}
	showSelector.value = true;
}

async function onEventSelect(event: EventReminder) {
	selectReminder.value = event
}
</script>

<style>
.container {
	padding: 20rpx;
}

.progress-container {
	margin-top: 20px;
	padding: 10px;
}

.progress-info {
	display: flex;
	justify-content: space-between;
	margin-bottom: 5px;
}

.progress-bar {
	width: 100%;
	height: 20px;
	background-color: #f0f0f0;
	border-radius: 10px;
	overflow: hidden;
}

.progress-inner {
	height: 100%;
	background-color: #007AFF;
	transition: width 0.3s ease;
}
</style>