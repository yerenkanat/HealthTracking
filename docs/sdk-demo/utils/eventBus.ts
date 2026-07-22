type EventCallback = (data : any) => void;

class EventBus {
	private static instance : EventBus;
	private events : Map<string, EventCallback[]>;

	private constructor() {
		this.events = new Map();
	}

	public static getInstance() : EventBus {
		if (!EventBus.instance) {
			EventBus.instance = new EventBus();
		}
		return EventBus.instance;
	}

	// 订阅事件
	public subscribe(event : string, callback : EventCallback) : void {
		if (!this.events.has(event)) {
			this.events.set(event, []);
		}
		this.events.get(event)?.push(callback);
	}

	// 发布事件
	public publish(event : string, data : any) : void {
		if (this.events.has(event)) {
			this.events.get(event)?.forEach(callback => {
				callback(data);
			});
		}
	}

	// 取消订阅
	public unsubscribe(event : string, callback : EventCallback) : void {
		if (this.events.has(event)) {
			const callbacks = this.events.get(event);
			if (callbacks) {
				const index = callbacks.indexOf(callback);
				if (index > -1) {
					callbacks.splice(index, 1);
				}
			}
		}
	}
}

export const eventBus = EventBus.getInstance();