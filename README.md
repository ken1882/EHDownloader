# EHDownloader
A CLI tool with multiple options to download the gallery you want

## 下載
https://github.com/ken1882/EHDownloader/releases

## 使用方式 | Usage

提供2種下載方式:
- 搜尋下載 (下載所有搜尋到的畫廊)
- 從檔案下載 (檔案內部含要下載的畫廊網址)


There're 2 methods you can download:
- Download from search result (Download all galleries found)
- DOwnload from file (The file contains the links to the galleries you want to download)

### 搜尋下載 | Download from search result
(此檔案會被當程始碼執行，千萬不要亂改)<br>
(Warnging: This file will be executed as the source code)

打開 `config.txt`, 可看到:<br>
Open `config.txt`, you can see:<br>

	{
	  :search_options => { # do not remove this

		# 關鍵字搜尋 | keyword search
		:filter => %{
		  language:chinese
		},

如同平時的搜尋功能, 如要撇除韓文結果則是:<br>
Just as the search function in the website, if you want to exclude korean:<br>

		:filter => %{
		  language:chinese -"language:korean"
		},

類別(category)

		# 類別 (1:搜尋 0:不搜尋, 以下的0/1的功能除非特別註明否則皆同)
    # 1: search this category, 0: don't (the 1/0 below means same unless noted)
		:types => {
		  :misc       => 1,
		  :doujinshi  => 1,
		  :manga      => 1,
		  :arist_cg   => 1,
		  :game_cg    => 1,
		  :image_set  => 1,
		  :cosplay    => 1,
		  :asian_porn => 1,
		  :non_h      => 1,
		  :western    => 1
		},

如不想搜尋 misc 和 western，則把1改0:<br>
If do not want to search MISC and WESTERN:<br>

		:types => {
		  :misc       => 0,
		  :doujinshi  => 1,
		  :manga      => 1,
		  :arist_cg   => 1,
		  :game_cg    => 1,
		  :image_set  => 1,
		  :cosplay    => 1,
		  :asian_porn => 1,
		  :non_h      => 1,
		  :western    => 0
		},

以下為進階搜尋內容<br>
Below are contents of advanced search<br>

		# 搜尋名稱 | search gallery name
		:s_name       => 1,

		# 搜尋tag | serch tag
		:s_tags       => 1,

		# 搜尋被刪除的本本 | search expunged gallery
		:s_deleted    => 1,

		# 最低評價星級 | Min. star rating
		:min_star     => 0,

		# 本本頁數 (預設為1~9999頁) | Pages between
		:page_between => [1, 9999],
		
		# 不啟用E站的預設過濾器 | Disable default filter in the website
		:disable_default_filter => 1,
	  }, # do not remove this

	  # 下載原圖需要登入的cookie, 若啟用則會因為流量大而容易被ban
    # Whether download original file, a working login cookie is required, 
    # beware that your internet traffic will be tremendously increased and may result a ban
	  :download_original      => 0,

	  # 僅蒐尋本本meta資料, 不載圖 | search meta only without download gallery
	  :meta_only              => 0,

	  # 下載圖片時的資料夾名稱使用全英文
    # Full-English folder title when downloading
	  :english_title          => 0,

	  # 每傳輸N次休息一次 (預設N=2)
    # Sleep for a time per N times of connections (Default N=2)
	  :fetch_loose_threshold  => 2,

	  # 每次休息秒數(預設10, 實際執行會再隨機+0~1秒)
    # Sleep duration in seconds (+0~1 sec in runtime)
	  :fetch_sleep_time       => 10,

	  # 額外的隨機休息秒數增加(0~N秒, 預設3)
    # Extra randomed sleep duration (0~N)
	  :fetch_sleep_rrange     => 3,

	  # 手動輸入抓取的範圍
    # Manually enter crawling page range
	  :set_start_page         => 0,
	}
  
### 從檔案下載 | Download from file
打開 `targets.txt`，每行一個網址，裡面以經有一些範例，取代掉即可<br>
Open `targets.txt`, one link per line and there're some examples insides already, just replace them.

### 功能 | Features

	[0] Exit                       # 離開程式
	[1] Download from `conig.txt`  # 從`config.txt` 下載
	[2] Retry failed downloads     # 重試失敗的下載
	[3] Resume a download          # 從中斷點繼續下載
	[4] Resume a meta collecting   # 繼續被中斷的meta
	[5] Download from file         # 從檔案下載
  
按下對應的數字按鍵即可執行該功能，若要中斷，則按下`Ctrl + C`，並可選擇是否斷點續傳<br>
Press the corresponding key to run the function, press `Ctrl + C` if you want to abort, and you can choose whether to save in order to continue this aborted download.
