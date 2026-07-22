<template>
	<view class="container">
		<view class="status-section">
			<view class="status-item">
				<text class="label">蓝牙状态:</text>
				<text :class="['status', statusClass]">{{ statusText }}</text>
			</view>
		</view>
		<view class="status-section">
			<view class="status-item">
				<text class="label">当前连接设备:</text>
				<text>{{ connectDevice }}</text>
			</view>
		</view>
		<text>附近蓝牙设备：</text>
		<view style="display: flex; align-items: center">
			<input type="text" placeholder="名称搜索指定设备" v-model="searchKeyword" />
			<button @click="handleSearch">搜索</button>
			<button @click="searchKeyword = ''">清空</button>
		</view>
		<scroll-view scroll-y class="box" style="overflow: scroll">
			<view class="item" v-for="item in filteredDeviceList" @click="handleClick(item)" :key="item.deviceId">
				<view>
					<text style="font-size: 25px; font-weight: 700">name: {{ item.name }}</text>
				</view>
				<view>
					<text>{{ item.deviceId }}</text>
				</view>
			</view>
		</scroll-view>
		<button @click="initBluetooth">初始化蓝牙</button>
		<button @click="discovery" :disabled="!isInit">搜索附近蓝牙设备</button>
		<button @click="discovery2" :disabled="!isInit">搜索附近蓝牙设备(包括已连接)</button>
		<text>{{ isSearching ? "搜索中" : "" }}</text>
		<button @click="makePair" :disabled="!isConnected">蓝牙配对</button>
		<button @click="unPair" :disabled="!isConnected">蓝牙取消配对</button>
		<button @click="closeConnection" :disabled="!isConnected">
			断开当前设备
		</button>
		<button @click="setMtu" :disabled="!isConnected">协商Mtu</button>
		<button @click="getMtu" :disabled="!isConnected">获取MTU</button>
		<view class="services-list" v-for="item in serviceList" :key="item.uuid">
			<view class="title"> Service Id: </view>
			<br />
			{{ item.uuid }}
			<view v-for="(char, index) in item.characteristics" :key="index" style="padding-left: 40rpx">
				<view class="title"> Characteristic </view>
				<br />
				UUID: {{ char.uuid }}
				<br />
				Properties: {{ char.props.join(",") }}
				<view v-if="char.properties['write']">
					<input type="text" v-model.trim="inputVal" />
					<button @click="sendData(char.uuid)">发送</button>
				</view>
			</view>
		</view>
		<text>监听的消息：</text>
		<scroll-view scroll-y class="box">
			<view class="item" v-for="item in receiveMsgList" :key="item.timestamp" style="width: 100%">
				<view style="display: flex; width: 100%">
					<view style="flex: 1; word-break: break-word">
						{{ item.resHex }}
					</view>
				</view>
			</view>
		</scroll-view>
	</view>
</template>
<script lang="ts" setup>
	import permission from '@/js_sdk/wa-permission/permission.js'
	// #ifdef APP
	import * as UTPair from '@/uni_modules/bluetooth-pair'
	// #endif
	import { Ref, computed, ref, watch } from "vue";
	import { starmaxSDK } from "../../libs/StarmaxSDK";
	import { NotifyType, PairResponse } from "../../libs/StarmaxSDK/types";
	import { useAppStore } from "../../store";
	import { writeBleData } from '../../utils/writeBleData';
	const sdk = starmaxSDK;
	const appStore = useAppStore();
	const intervalTimer = ref(null);
	const connectDevice = ref();
	const inputVal = ref("");
	const isInit = ref(false);
	const isConnected = ref(false);
	const isSearching = ref(false);
	const isListening = ref(false);
	const deviceId = ref("");
	const serviceId = ref("");
	const mtu = ref(0);
	const searchKeyword = ref("");
	// 监听的特征值
	const notifyCharacId = ref("");
	// 写入的特征值
	const writeCharacId = ref("");
	const statusClass = computed(() =>
		isConnected.value ? "status-connected" : "status-inactive"
	);
	const statusText = computed(() => (isConnected.value ? "已连接" : "未连接"));
	// 搜索到的蓝牙设备列表
	const blueDeviceList = ref([]);
	const filteredDeviceList = ref([]);
	// 该设备的服务列表
	const serviceList = ref([]);
	// 接收到的消息列表
	const receiveMsgList = ref([]);
	function handleSearch() {
		if (!searchKeyword.value) {
			// 如果搜索关键词为空，显示所有设备
			filteredDeviceList.value = [...blueDeviceList.value];
			return;
		}
		// 根据关键词过滤设备
		filteredDeviceList.value = blueDeviceList.value.filter(
			(device) =>
				device.name &&
				device.name.toLowerCase().includes(searchKeyword.value.toLowerCase())
		);
		if (filteredDeviceList.value.length === 0) {
			uni.showToast({
				title: "未找到匹配设备",
				icon: "none",
			});
		}
	}
	function hexToArrayBuffer(hexStr) {
		// 去掉可能的空格
		hexStr = hexStr.replace(/\s+/g, "");
		if (hexStr.length % 2 !== 0) {
			throw new Error("十六进制字符串长度必须为偶数");
		}

		let buffer = new ArrayBuffer(hexStr.length / 2);
		let dataView = new Uint8Array(buffer);
		for (let i = 0; i < hexStr.length; i += 2) {
			dataView[i / 2] = parseInt(hexStr.substr(i, 2), 16);
		}
		return buffer;
	}
	function initBluetooth() {
		uni.openBluetoothAdapter({
			success(res) {
				console.log("初始化蓝牙成功");
				isInit.value = true;
				uni.showToast({
					title: "初始化成功",
					icon: "success",
				});
				console.log(res);
			},
			fail(err) {
				console.log("初始化蓝牙失败", err);
				if (err.errno == 103) {
					uni.showModal({
						title: "提示",
						content: "请允许小程序使用蓝牙权限",
						showCancel: false,
					});
				}
			},
		});
	}

	function discovery2() {
		uni.getBluetoothDevices({
			success(res) {
				blueDeviceList.value = res.devices;
				filteredDeviceList.value = res.devices;
			},
			fail(err) {
				console.log("搜索蓝牙失败", err);
			},
		});
	}
	// 【2】开始搜寻附近设备
	function discovery() {
		if (isSearching.value) return;
		uni.startBluetoothDevicesDiscovery({
			success(res) {
				console.log("开始搜索");
				isSearching.value = true;
				// 开启监听回调
				uni.onBluetoothDeviceFound(handleFound);
			},
			fail(err) {
				uni.showModal({
					title: "提示",
					content: `搜索失败，请重试 ${err.errMsg}`,
					showCancel: false,
				});
				console.log("搜索失败", err);
			},
		});
	}

	function handleClick(item) {
		uni.showModal({
			content: "连接该设备?",
			success(res) {
				if (res.confirm) {
					handleConnect(item);
				}
			},
		});
	}
	function containsSequence(data, sequence) {
		for (let i = 0; i <= data.length - sequence.length; i++) {
			let match = true;
			for (let j = 0; j < sequence.length; j++) {
				if (data[i + j] !== sequence[j]) {
					match = false;
					break;
				}
			}
			if (match) return true;
		}
		return false;
	}


	// 【3】找到新设备就触发该方法
	function handleFound(res) {
		if (!res.devices[0].name) return;
		if (
			!blueDeviceList.value.some(
				(item) => item.deviceId == res.devices[0].deviceId
			)
		) {
			const deviceInfo = res.devices[0]
			const advertisData = new Uint8Array(deviceInfo.advertisData)
			const target = [0x00, 0x01]
			const flag = containsSequence(advertisData,target)
			const includeNameList = ['GTS']
			// 通过广播过滤
			if(flag){
				blueDeviceList.value.push(res.devices[0]);
			}
			// 也可通过名称过滤
			// const nameFlag = includeNameList.some(name => deviceInfo.name.includes(name))
			// if(flag && nameFlag) {
			// 	blueDeviceList.value.push(res.devices[0]);
			// }
			
			// 更新过滤后的列表
			if (!searchKeyword.value) {
				filteredDeviceList.value = [...blueDeviceList.value].sort((a, b) => {
					return b.RSSI - a.RSSI; // 从强到弱
				});
			} else {
				handleSearch();
			}
		}
		// const filteredDevice = res.devices.find((item) => item.name == "GTS10-13ef");
		// const isInclude = blueDeviceList.value.some(
		//   (item) => item?.deviceId == filteredDevice?.deviceId
		// );
		// if (filteredDevice && !isInclude) {
		//   blueDeviceList.value.push(filteredDevice);
		// }
	}
	function iosGetMac(buffer) {
		const hexArr = Array.prototype.map.call(
			new Uint8Array(buffer),
			function (bit) {
				return ('00' + bit.toString(16)).slice(-2)
			}
		)
		return hexArr.join(':')
	}
	function connect(deviceId) {
		return new Promise((resolve, reject) => {
			uni.createBLEConnection({
				deviceId: deviceId,
				timeout: 10000,
				success: async (res) => {
					setTimeout(() => {
						this.setMtu(deviceId)
					}, 1000)
					await new Promise((resolve) =>
						setTimeout(() => {
							resolve(1)
						}, 1000)
					)
					await getServices()
					isConnected.value = true
					resolve(res)
				},
				fail(err) {
					console.log('连接蓝牙失败：', err)
					if (err.code === -1) {
						resolve(1)
					} else {
						reject(err)
					}
				},
			})
		})
	}
	// 【4】连接设备
	function handleConnect(data) {
		uni.showLoading({});
		const advertisData = new Uint8Array(data.advertisData).slice(2, 8)
		const macAddress = iosGetMac(advertisData)
		console.log('macAddress' + '--------------', macAddress);
		deviceId.value = data.deviceId;

		console.log('deviceId' + '--------------', deviceId.value);
		uni.createBLEConnection({
			deviceId: deviceId.value,
			success(res) {
				setTimeout(setMtu, 1000);
				isConnected.value = true;
				connectDevice.value = data.name;
				setTimeout(getServices, 1000);
				stopDiscovery();
			},
			fail(err) {
				console.log(err);
				uni.showModal({
					title: "提示",
					content: `连接失败，请重试 ${err.errMsg}`,
					showCancel: false,
				});
				uni.hideLoading();
			},
		});
	}
	// 【5】停止搜索
	function stopDiscovery() {
		uni.stopBluetoothDevicesDiscovery({
			success(res) {
				isSearching.value = false;
				console.log("停止成功");
				console.log(res);
			},
			fail(err) {
				console.log("停止失败");
				console.error(err);
			},
		});
	}
	// 【6】获取服务
	function getServices() {
		return new Promise((resolve, reject) => {
			uni.getBLEDeviceServices({
				deviceId: deviceId.value,
				async success(res) {
					await new Promise((resolve) =>
						setTimeout(() => {
							resolve(1)
						}, 1000)
					)
					const { services } = res;
					console.log("services" + "--------------", services);
					const filteredServices = services.filter((item) => {
						return item.uuid.toLowerCase().startsWith("6e400001");
					});
					serviceId.value = filteredServices[0].uuid;
					serviceList.value = await Promise.all(
						filteredServices.map(async (service) => {
							const characteristics = (await getCharacteristics(
								service.uuid
							)) as any;
							return {
								uuid: service.uuid,
								characteristics: characteristics,
							};
						})
					);
					writeCharacId.value = serviceList.value[0].characteristics.find(
						(char) => {
							return char.properties["write"];
						}
					).uuid;
					notifyCharacId.value = serviceList.value[0].characteristics.find(
						(char) => {
							return char.properties["notify"];
						}
					).uuid;
					await startNotify();
					appStore.init({
						deviceId: deviceId.value,
						serviceId: serviceId.value,
						writeCharacId: writeCharacId.value,
						notifyCharacId: notifyCharacId.value,
						mtu: mtu.value,
					});
					resolve(res)
				},
			});
		})
	}
	// 【7】获取特征值
	async function getCharacteristics(serviceId) {
		return new Promise((resolve, reject) => {
			uni.getBLEDeviceCharacteristics({
				deviceId: deviceId.value,
				serviceId: serviceId,
				success(res) {
					console.log("获取特征值成功：", res);
					res.characteristics.forEach((char : any) => {
						char.props = Object.keys(char.properties).filter(
							(key) => char.properties[key]
						);
					});
					resolve(res.characteristics);
				},
				fail(err) {
					uni.showModal({
						title: "提示",
						content: `获取特征值失败，请重试 ${err.errMsg}`,
						showCancel: false,
					});
					console.error("获取特征值失败：", err);
					reject(err);
				},
			});
		});
	}
	// 【8】开启消息监听
	function startNotify() {
		return new Promise((resolve, rej) => {
			uni.showLoading();
			uni.notifyBLECharacteristicValueChange({
				deviceId: deviceId.value, // 设备ID，在【4】里获取到
				serviceId: serviceId.value, // 服务UUID，在【6】里能获取到
				characteristicId: notifyCharacId.value, // 特征值，在【7】里能获取到
				state: true,
				success(res) {
					uni.showToast({
						icon: "success",
						title: "成功",
					});
					// 接受消息的方法
					isListening.value = true;
					listenValueChange();
					resolve(1)
				},
				fail(err) {
					uni.showModal({
						title: "提示",
						content: `监听失败，请重试 ${err.errMsg}`,
						showCancel: false,
					});
					console.log("开启监听失败：", err);
				},
			});
		})
	}
	let notifyCb = (res : any) => {
		let resHex = (ab2hex(res.value) as string).toUpperCase();
		console.log("接收到16进制字符串" + "-----------", resHex);
		const now = new Date();
		const timeString =
			now.getHours().toString().padStart(2, "0") +
			":" +
			now.getMinutes().toString().padStart(2, "0") +
			":" +
			now.getSeconds().toString().padStart(2, "0") +
			"." +
			now.getMilliseconds().toString().padStart(3, "0");

		const msgObj = {
			timestamp: Date.now(),
			time: timeString,
			resHex,
			length: res.value.byteLength,
		};
		console.log('msgObj' + '--------------', msgObj);
		receiveMsgList.value.unshift(msgObj);
		const resetType = [
			NotifyType.CloseDevice,
			NotifyType.Reset,
			NotifyType.Unpair,
		];
		starmaxSDK
			.notify(res.value as unknown as ArrayBuffer)
			.then((result) => {
				if (resetType.includes(result.type)) {
					handleReset();
				}
				console.log('result' + '--------------', result);
				appStore.updateNotifyValue(result);
			})
			.catch((err) => {
				console.log("err" + "--------------", err);
			});
	}
	// 【9】监听消息变化
	function listenValueChange() {
		uni.onBLECharacteristicValueChange(notifyCb);
	}
	// 【10】发送数据
	function sendData(characteristicId) {
		// 移除可能的空格
		const hexString = inputVal.value.replace(/\s/g, "");
		// 创建一个长度为十六进制字符串一半的缓冲区（因为每两个字符表示一个字节）
		const buffer = new ArrayBuffer(hexString.length / 2);
		const uint8Array = new Uint8Array(buffer);

		// 将十六进制字符串转换为字节数组
		for (let i = 0; i < hexString.length; i += 2) {
			uint8Array[i / 2] = parseInt(hexString.substr(i, 2), 16);
		}
		console.log("deviceId" + "--------------", deviceId.value);
		console.log("serviceId" + "--------------", serviceId.value);
		console.log("charac" + "--------------", characteristicId);
		console.log("buffer" + "--------------", buffer);
		uni.writeBLECharacteristicValue({
			deviceId: deviceId.value,
			serviceId: serviceId.value,
			characteristicId,
			value: buffer,
			writeType: "write",
			success(res) {
				console.log("发送成功：", res);
			},
			fail(err) {
				console.error("发送失败：", err);
			},
		});
	}
	// 【11】关闭设备连接
	function closeConnection() {
		uni.showModal({
			title: "提示",
			content: "确定要关闭连接吗？",
			success: function (res) {
				if (res.confirm) {
					uni.closeBLEConnection({
						deviceId: deviceId.value,
						success() {
							handleReset();
							uni.showToast({
								icon: "success",
								title: "关闭连接成功",
							});
						},
						fail(err) {
							uni.showModal({
								title: "提示",
								content: `关闭连接失败，请重试 ${err.errMsg}`,
								showCancel: false,
							});
							console.log("关闭连接失败-----", err);
						},
					});
				}
			},
		});
	}
	// 【12】协商MTU
	function setMtu() {
		const platform = uni.getDeviceInfo().platform;
		console.log('platfrom' + '--------------', platform);
		// ios不支持
		if (platform != "android") return;
		listenMtuChange();
		for (let i = 0; i < 3; i++) {
			uni.setBLEMTU({
				deviceId: deviceId.value,
				mtu: 512,
				success(res) {
					console.log('res' + '--------------', res);
					appStore.mtu = res.mtu;
					console.log("协商mtu成功", res);
				},
				fail(err) {
					console.log("协商mtu失败", err);
				},
			});
		}
	}
	// 【13】获取MTU
	function getMtu() {
		console.log('mtu' + '--------------', appStore.mtu);
		wx.getBLEMTU({
			deviceId: deviceId.value,
			success(res) {
				console.log("Mtu-----", res);
			},
			fail(err) {
				console.log("获取Mtu失败", err);
			},
		});
	}

	// ArrayBuffer转16进度字符串示例
	function ab2hex(buffer) {
		const hexArr = Array.prototype.map.call(
			new Uint8Array(buffer),
			function (bit) {
				return ("00" + bit.toString(16)).slice(-2);
			}
		);
		return hexArr.join("");
	}
	function handleReset() {
		searchKeyword.value = "";
		isConnected.value = false;
		connectDevice.value = "";
		blueDeviceList.value = [];
		filteredDeviceList.value = [];
		serviceList.value = [];
		notifyCharacId.value = "";
		writeCharacId.value = "";
		inputVal.value = "";
		receiveMsgList.value = [];
		// 移除之前的消息监听
		notifyCb = function () { }
		if (wx && wx.offBLECharacteristicValueChange) {
			wx.offBLECharacteristicValueChange();
		}
	}
	function makePair() {
		// #ifdef APP
		const platform = uni.getDeviceInfo().platform;
		if (platform == "android") {
			const res = UTPair.pair(deviceId.value)
			console.log('UTPair' + '--------------', res);
		} else {
			UTPair.iosPair(deviceId.value)
		}
		// #endif
		// #ifdef MP-WEIXIN
		uni.makeBluetoothPair({
			deviceId: deviceId.value,
			pin: "",
			success: function (res) {
				console.log("配对成功" + "--------------", res);
			},
			fail: function (err) {
				console.log("配对失败" + "--------------", err);
			},
		});
		// #endif
	}
	function unPair() {
		const platform = uni.getDeviceInfo().platform;
		if (platform == "android") {
			const res = UTPair.unpair(deviceId.value)
			handleReset()
			console.log('UTUnPair' + '--------------', res);
		} else {
			UTPair.iosPair(deviceId.value)
		}
	}
	function listenMtuChange() {
		if (!uni.onBLEMTUChange) return;
		uni.onBLEMTUChange((res) => {
			console.log("mtu change" + "--------------", res.mtu);
			appStore.mtu = res.mtu;
		});
	}
	function getEnumKeyByValue(enumObj : any, value : number) : string {
		return Object.keys(enumObj).find(key => enumObj[key] === value) || '';
	}
</script>

<style></style>