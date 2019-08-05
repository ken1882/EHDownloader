# EHDownloader
含有許多功能、可斷點續傳，專門拿來下載熊貓網表裏站的小黑窗程式<br>
A CLI based tool with multiple options including resume progress feature to download the gallery you want, supports both e-hentai and exhentai.

## 下載 | Download
https://github.com/ken1882/EHDownloader/releases

## 使用方式 | Usage

如需使用Cookie, 推薦使用 [EditThisCookie](https://chrome.google.com/webstore/detail/editthiscookie/fngmhnnpilhplaeedifhccceomclgfbg)輸出成JSON並到`cookie.json`全部貼上並取代。如果你的在e-hentai所輸出的Cookie是贊助者cookie，搜尋功能理論上將會找到更多結果。[如何導入Cookie?](https://github.com/ken1882/EHDownloader/blob/master/README.md#%E5%B0%8E%E5%85%A5cookie--import-cookie)<br>
If you want to use Cookie, recommending using [EditThisCookie](https://chrome.google.com/webstore/detail/editthiscookie/fngmhnnpilhplaeedifhccceomclgfbg) to export them and paste on `cookie.json`, replacing what it's inside. If you're a sponsor you should be able to search with more results on e-hentai. [How to import cookie?](https://github.com/ken1882/EHDownloader/blob/master/README.md#%E5%B0%8E%E5%85%A5cookie--import-cookie)<br>

如果Cookie成功導入，則本程式將會連線至熊貓網下載；如果連不上或沒cookie則會連線至表站。<br>
If cookie has imported successfully, this program will connect to exhentai; it'll connect to e-hentai failed to connet to sad panda.

提供2種下載方式:
- 搜尋下載 (下載所有搜尋到的畫廊)
- 從檔案下載 (檔案內部含要下載的畫廊網址)

This program provides 2 methods to download:
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

		# 本本頁數, 即搜尋含有多少圖片的畫廊 (預設為1~9999頁)
		# How many images the gallery you want to search between?
		:page_between => [1, 9999],
		
		# 不啟用E站的預設過濾器 | Disable default filter in the website
		:disable_default_filter => 1,
	  }, # do not remove this

	  # 是否下載原圖，若啟用則需要可成功登入的cookie, 注意有可能因為流量大而更容易被ban或超過流量上限
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

	  # 下載原圖時的最久容忍秒數
      # Maximum seconds to wait for downloading original image
	  :timeout_original       => 30,

	  # 一般下載時的最久容忍秒數
      # Maximum seconds to wait for downloading normal image
	  :timeout_normal         => 10,
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

若要暫停(如切換網路或VPN)，則先啟用cmd的[快速編輯模式](https://answers.microsoft.com/zh-hant/windows/forum/windows_7-files/%E5%91%BD%E4%BB%A4%E6%8F%90%E7%A4%BA%E5%AD%97/97d2d0d2-ad06-410d-a297-cdc92b3feac8)，接著在小黑窗的範圍內隨便選取一個範圍反白即可；之後按右鍵則可繼續。<br>
If you want to pause(maybe you need to switch internet connection or VPN), first [enable the quick edit mode in cmd](https://www.google.com/search?q=how+to+enable+quick+edit+mode), then select anywhere in the window to pause; to resume, just right click anywhere in the window.

## 導入Cookie | Import cookie
下載[EditThisCookie](https://chrome.google.com/webstore/detail/editthiscookie/fngmhnnpilhplaeedifhccceomclgfbg)後，到網站上點選該擴充功能圖示，便會出現以下視窗(若只有一個cookie代表沒有登入)<br>
After download [EditThisCookie](https://chrome.google.com/webstore/detail/editthiscookie/fngmhnnpilhplaeedifhccceomclgfbg), go to the website and click on the add-on icon, the window as below should popup (if it only has 1 cookie, this means you haven't login in yet.)<br>
![](https://i.imgur.com/st92INr.png)<br>

點選上圖紅圈處導出cookie, 內容將自動複製到剪貼簿<br>
Click on the icon that red circle in the image above indicates to export your cookie.<br>
![](https://i.imgur.com/96HuIgw.png)

包含主程式在內的壓縮檔含有以下內容<br>
The zipped file contain the files as below shows<br>
![](https://i.imgur.com/HOBBO7Y.png)
* cacert.perm: HTTPS憑證 | https certificate file.
* config.txt: 搜尋下載的選項配置, 使用方式見上方 | Configuration file of the search download, for usage see the section above.
* cookie.json: 要導入的Cookie檔案 | The import cookie file.
* EHDownloader.exe: 主程式, 除直接開啟外可接受"-v"參數來查詢版本 | Main program, besides open directly, you can also pass "-v" argument to see the version.
* README.md: 部分說明文件 | Part of this instruction document.
* targets.txt: 從檔案下載的導入文件, 使用方式見上方 | Source file of the "Download from file", for usage see the section above.

解壓縮後打開`cookie.json`, 此處使用有自定義佈景主題的[notepad++](https://notepad-plus-plus.org/zh/)<br>
Extract the files and open `cookie.json`, this instruction use the [notepad++](https://notepad-plus-plus.org) with customed theme.<br>
![](https://i.imgur.com/Izg8mrE.png)

將原本的內容全部刪除後, 貼上先前複製的cookie內容接著再儲存檔案即可完成<br>
Delete the text that already inside the file, paste the cookie content we exported earlier then save the file. Done.<br>
![](https://i.imgur.com/AVIPvmS.png)
