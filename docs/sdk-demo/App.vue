<script>
	export default {
		onLaunch: function() {
			console.log('App Launch')
		},
		onShow: function() {
			console.log('App Show')
		},
		onHide: function() {
			console.log('App Hide')
		}
	}
</script>

<style>
	.container {
		padding: 20px;
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

	.label {
		font-size: 16px;
		margin-right: 10px;
	}

	.status {
		font-size: 16px;
		font-weight: bold;
	}

	.status-inactive {
		color: #999;
	}

	.status-disconnected {
		color: #ff5252;
	}

	.status-connecting {
		color: #ffb300;
	}

	.status-connected {
		color: #4caf50;
	}

	.box {
		width: 100%;
		height: 300rpx;
		box-sizing: border-box;
		margin-bottom: 20rpx;
		border: 2px solid dodgerblue;
	}

	.item {
		box-sizing: border-box;
		padding: 10rpx;
		border-bottom: 1px solid #ccc;
	}

	button {
		margin-bottom: 20rpx;
	}

	.data-section {
		margin-top: 20px;
	}

	.section-title {
		font-size: 16px;
		font-weight: bold;
		margin-bottom: 10px;
		display: block;
	}

	input {
		border: 1px solid dodgerblue;
		font-size: 20px;
	}

	.data-input {
		width: 100%;
		height: 40px;
		border: 1px solid #ddd;
		border-radius: 4px;
		padding: 0 10px;
		margin-bottom: 10px;
	}

	.title {
		font-weight: 700;
		font-size: 18px;
	}
	.spliter{
		width: 100%;
		height: 2px;
		margin: 25px 0;
		background-color: #ccc;
		position: relative;
	}
	.spliter-label{
		position: absolute;
		left: 20px;
		top: 50%;
		transform: translateY(-50%);
		background-color: #fff;
		font-size: 23px;
		padding: 0 5px;
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