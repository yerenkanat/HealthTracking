import { defineStore } from 'pinia'
import { eventBus } from '../utils/eventBus'

interface InitParams {
	deviceId: string,
	serviceId: string,
	writeCharacId: string,
	notifyCharacId: string,
	mtu: number
}

export const useAppStore = defineStore('app', {
	state: () => ({
		deviceId: "",
		serviceId: "",
		writeCharacId: "",
		notifyCharacId: "",
		mtu: 0,
		isInit: false,
		sentByte: 0,
		notifyValue: null
	}),
	actions: {
		init(params: InitParams) {
			this.deviceId = params.deviceId
			this.serviceId = params.serviceId
			this.writeCharacId = params.writeCharacId
			this.notifyCharacId = params.notifyCharacId
			this.mtu = params.mtu
			// 标记初始化完成
			console.log('mtu为' + '--------------',params.mtu);
			this.isInit = true
		},
		setInit(status: boolean) {
			this.isInit = status
		},
		// 更新蓝牙特征值变化的数据
		updateNotifyValue(value: ArrayBuffer) {
			this.notifyValue = value
			// 发布蓝牙特征值变化事件
			eventBus.publish('notifyValueChange', value)
		},
		updateSendByte(byte: number) {
			this.sentByte += byte
		}
		// 清除蓝牙特征值变化的数据
		// clearNotifyValue() {
		// 	this.notifyValue = null
		// }
	}
})