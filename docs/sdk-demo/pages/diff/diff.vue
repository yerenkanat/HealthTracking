<template>
	<view class="container">
		<button @click="selectFileFromChat">选择聊天文件进行差分升级</button>
		<span>差分升级状态：{{ diffStatus }}</span>
		<view class="progress-container">
			<view class="progress-info">
				<text>传输进度：</text>
				<text>{{ progressPercentage }}%</text>
			</view>
			<view class="progress-bar">
				<view class="progress-inner" :style="{ width: progressPercentage + '%' }"></view>
			</view>
		</view>
	</view>
</template>

<script setup lang="ts">
	import {
		onMounted,
		onUnmounted,
		computed,
		ref,
		toRef
	} from "vue";
	import { starmaxSDK, bleFileSender } from "../../libs/StarmaxSDK";
	import { useAppStore } from "../../store";
	import { writeBleData } from "../../utils/writeBleData";
	import { NotifyType } from "../../libs/StarmaxSDK/types";
	import { eventBus } from "../../utils/eventBus";
	import { useNotify } from "../../hooks/useNotify";
	import { splitArrayBuffer } from "../../libs/StarmaxSDK/utils";
	const filePath = '/static/ota.bin'
	const sdk = starmaxSDK
	const appStore = useAppStore()
	let progressPercentage = ref(0)
	let fileSize = ref(0)
	const {
		notifySuccessCb
	} = useNotify()
	notifySuccessCb((res) => {
		if (res.type == NotifyType.Diff) {
			bleFileSender.notifyDiff(res.data)
			updateDiffStatus()
		}
	})
	const localDiffStatus = ref('')
	const diffStatus = computed(() => {
		return localDiffStatus.value || bleFileSender.diffStatus
	})
	function updateDiffStatus() {
		localDiffStatus.value = bleFileSender.diffStatus
	}
	// 文件发送监听器
	const fileSenderListener = {
		onSuccess: () => {
			uni.showToast({
				icon: "success",
				title: "差分升级成功"
			})
		},
		onFailure: (status : number) => {
			console.log('文件发送失败:', status);
			uni.showToast({
				title: '文件发送失败',
				icon: 'error'
			});
		},
		onProgress: (progress : number) => {
			progressPercentage.value = progress;
		},
		onSend: (buffer : ArrayBuffer) => {
			writeBleData(buffer)
		},
		onSendComplete: () => {
			bleFileSender.sendDiffComplete()
		},
	};

	function sendDiffHead() {
		localDiffStatus.value = "发送差分升级头"
		bleFileSender.sendDiffHeader()
	}


	// 从微信聊天记录选择差分升级文件
	async function selectFileFromChat() {
		await readFile(filePath)
		sendDiffHead()
		// wx.chooseMessageFile({
		// 	count: 1,
		// 	type: 'file',
		// 	async success(res) {
		// 		await readFile(res.tempFiles[0].path)
		// 		sendDiffHead()
		// 	}
		// })
	}
	async function readFile(filePath : string) {
		const res : any = await getFileInfo(filePath)
		const fileBuffer = res.arrayBuffer;
		fileSize.value = res.size
		bleFileSender.initFile(fileBuffer, fileSenderListener)
		uni.showToast({
			icon: "success",
			title: "文件读取成功"
		})
	}


	// 读取文件获得arrayBuffer（小程序用）
	function getFileInfoWx(filePath : string) {
		return new Promise((resolve, reject) => {
			let fileManager = uni.getFileSystemManager();
			fileManager.readFile({
				filePath,
				success: (res) => {
					// 默认返回 ArrayBuffer 格式
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
	const getFileInfo = (filePath : string) => {
		return new Promise((resolve, reject) => {
			plus.io.requestFileSystem(plus.io.PRIVATE_WWW, (fs) => {
				fs.root.getFile(filePath, {
					create: false
				}, (fileEntry) => {
					fileEntry.file((file) => {
						console.log('file：', file);
						const fileReader = new plus.io.FileReader();
						fileReader.readAsDataURL(file);

						fileReader.onload = (evt : any) => {
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
</script>

<style>
</style>