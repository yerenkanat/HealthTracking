import { onMounted, onUnmounted } from 'vue';
import { eventBus } from '../utils/eventBus';

export function useNotify() {
	let successCb: ((res: any) => void) | null = null;
	let errorCb: ((res: any) => void) | null = null;
	let notifyCb: ((res: any) => void) | null = null;
	// 处理蓝牙特征值变化的回调函数
	const notifySuccessCb = (callback: (res: any) => void) => {
		successCb = callback;
	};
	const notifyErrorCb = (callback: (res: any) => void) => {
		errorCb = callback
	}
	const notifyCallCb = (callback: (res: any) => void) => {
		notifyCb = callback
	}

	const processNotify = (newValue: ArrayBuffer) => {
		successCb && successCb(newValue);
	};

	onMounted(() => {
		// 订阅蓝牙特征值变化事件
		eventBus.subscribe('notifyValueChange', processNotify);
	});

	onUnmounted(() => {
		// 取消订阅蓝牙特征值变化事件
		eventBus.unsubscribe('notifyValueChange', processNotify);
	});

	return {
		notifySuccessCb,
		notifyErrorCb
	};
}