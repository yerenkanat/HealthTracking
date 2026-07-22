import { useAppStore } from "../store";

const BLE_ERROR_MAP = {
  10000: "未初始化蓝牙适配器",
  10001: "当前蓝牙适配器不可用",
  10002: "没有找到指定设备",
  10003: "连接失败",
  10004: "没有找到指定服务",
  10005: "没有找到指定特征值",
  10006: "当前连接已断开",
  10007: "当前特征值不支持此操作",
  10008: "其余所有系统上报的异常",
  10009: "系统版本低于 4.3 不支持 BLE",
  10010: "已连接",
  10011: "配对设备需要配对码",
  10012: "连接超时",
  10013: "连接 deviceId 为空或者是格式不正确",
};

/**
 * 根据 MTU 大小对数据进行分包并发送
 * @param data 要发送的数据
 */
export function writeBleData(data: ArrayBuffer) {
    const appStore = useAppStore();
    // const mtu = Math.min(appStore.mtu, 512)|| 23; // 如果没有 MTU 则使用默认值 23
		const mtu = 247
    const chunkSize = mtu - 3; // 预留3个字节用于包头
    // 将 ArrayBuffer 转换为 Uint8Array
    const uint8Array = new Uint8Array(data);
    let offset = 0;
    // 递归发送数据包
    function sendNextChunk() {
        if (offset >= uint8Array.length) {
            return;
        }
        
        // 获取当前数据包
        const chunk = uint8Array.slice(offset, offset + chunkSize);
        offset += chunk.length;
        // 发送数据包
        uni.writeBLECharacteristicValue({
            deviceId: appStore.deviceId,
            serviceId: appStore.serviceId,
            characteristicId: appStore.writeCharacId,
            value: chunk.buffer,
            success: () => {
							console.log('发送的chunk大小' + '--------------',chunk.length);
							// sendNextChunk()
							setTimeout(sendNextChunk, 20)
            },
            fail: (err) => {
                console.error('发送失败：', err);
            }
        });
    }
    
    // 开始发送第一个数据包
    sendNextChunk();
}
