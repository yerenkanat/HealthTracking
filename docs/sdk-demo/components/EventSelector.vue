<template>
  <view class="event-selector" v-if="show">
    <view class="mask" @click="onClose"></view>
    <view class="content">
      <view class="header">
        <text class="title">选择事件提醒</text>
        <text class="close" @click="onClose">×</text>
      </view>
      <scroll-view class="event-list" scroll-y>
        <view v-for="event in events" :key="event.reminderIndex" class="event-item" @click="onSelect(event)">
          <view class="event-info">
            <text class="event-name">{{ event.content }}</text>
            <text class="event-id">ID: {{ event.reminderIndex }}</text>
            <text class="event-name">time: {{ event.hour }}:{{ event.minute }}</text>
          </view>
        </view>
      </scroll-view>
    </view>
  </view>
</template>

<script setup lang="ts">
import { ref, defineProps, defineEmits } from 'vue';
import { EventReminder } from '../utils/types';

// 声明全局变量类型
declare const uni: any;

interface Props {
  show: boolean;
  events: EventReminder[];
}

const props = withDefaults(defineProps<Props>(), {
  show: false,
  events: () => []
});

const emit = defineEmits<{
  (e: 'close'): void;
  (e: 'select', event: EventReminder): void;
}>();

const onClose = () => {
  emit('close');
};

const onSelect = (event: EventReminder) => {
  emit('select', event);
  onClose();
};
</script>

<style>
.event-selector {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 999;
}

.mask {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(0, 0, 0, 0.5);
}

.content {
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  background-color: #fff;
  border-radius: 20rpx 20rpx 0 0;
  padding: 30rpx;
  max-height: 70vh;
}

.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20rpx;
}

.title {
  font-size: 32rpx;
  font-weight: bold;
}

.close {
  font-size: 40rpx;
  color: #999;
  padding: 10rpx;
}

.event-list {
  max-height: calc(70vh - 100rpx);
}

.event-item {
  padding: 20rpx;
  border-bottom: 1rpx solid #eee;
}

.event-info {
  display: flex;
  flex-direction: column;
  gap: 10rpx;
}

.event-name {
  font-size: 28rpx;
  color: #333;
}

.event-id {
  font-size: 24rpx;
  color: #999;
}
</style>