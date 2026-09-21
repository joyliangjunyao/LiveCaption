import Foundation

/// Source copy | Japanese | Korean | French | German | Spanish.
/// Keep one row per UI message. Audio transcripts never use this table.
enum AdditionalInterfaceCopy {
    static let translations: [InterfaceLanguage: [String: String]] = {
        let languages: [InterfaceLanguage] = [.japanese, .korean, .french, .german, .spanish]
        var result: [InterfaceLanguage: [String: String]] = [:]
        for row in rows.replacingOccurrences(of: "\\u{20}", with: " ").split(separator: "\n") {
            let fields = row.components(separatedBy: "|")
            precondition(fields.count == 6, "Invalid interface translation row")
            for (index, language) in languages.enumerated() {
                result[language, default: [:]][fields[0]] = fields[index + 1]
            }
        }
        return result
    }()

    private static let rows = """
    继续|続ける|계속|Continuer|Weiter|Continuar
    退出 LiveCaption_ZH-CN|LiveCaption_ZH-CN を終了|LiveCaption_ZH-CN 종료|Quitter LiveCaption_ZH-CN|LiveCaption_ZH-CN beenden|Salir de LiveCaption_ZH-CN
    正在加载 |読み込み中：|로딩 중: |Chargement : |Wird geladen: |Cargando:\u{20}
    退出 LiveCaption|LiveCaption を終了|LiveCaption 종료|Quitter LiveCaption|LiveCaption beenden|Salir de LiveCaption
    界面语言|表示言語|인터페이스 언어|Langue de l’interface|Oberflächensprache|Idioma de la interfaz
    语言|言語|언어|Langue|Sprache|Idioma
    界面语言与字幕翻译目标语言分别设置。|表示言語と字幕の翻訳先は別々に設定できます。|인터페이스 언어와 자막 번역 언어는 별도로 설정합니다.|La langue de l’interface est indépendante de la langue de traduction.|Oberflächen- und Übersetzungssprache werden getrennt eingestellt.|El idioma de la interfaz es independiente del idioma de traducción.
    剪切|切り取り|잘라내기|Couper|Ausschneiden|Cortar
    复制|コピー|복사|Copier|Kopieren|Copiar
    粘贴|ペースト|붙여넣기|Coller|Einfügen|Pegar
    全选|すべて選択|모두 선택|Tout sélectionner|Alles auswählen|Seleccionar todo
    字幕|字幕|자막|Sous-titres|Untertitel|Subtítulos
    说话人|話者|화자|Locuteurs|Sprecher|Hablantes
    翻译语言|翻訳先の言語|번역 언어|Langue de traduction|Übersetzungssprache|Idioma de traducción
    说话人断句|話者ごとに区切る|화자별 구분|Séparer par locuteur|Nach Sprecher trennen|Separar por hablante
    输入来源|音声入力|오디오 소스|Source audio|Audioquelle|Fuente de audio
    开启|オン|켜기|Activé|Ein|Activado
    关闭|オフ|끄기|Désactivé|Aus|Desactivado
    不显示|非表示|표시 안 함|Masquer|Ausblenden|Ocultar
    不显示翻译|翻訳を非表示|번역 표시 안 함|Masquer la traduction|Übersetzung ausblenden|Ocultar traducción
    暂停识别|認識を一時停止|인식 일시 정지|Suspendre la reconnaissance|Erkennung pausieren|Pausar reconocimiento
    开始识别|認識を開始|인식 시작|Démarrer la reconnaissance|Erkennung starten|Iniciar reconocimiento
    停止识别|認識を停止|인식 중지|Arrêter la reconnaissance|Erkennung stoppen|Detener reconocimiento
    停止录音|録音を停止|녹음 중지|Arrêter l’enregistrement|Aufnahme stoppen|Detener grabación
    开始录音|録音を開始|녹음 시작|Démarrer l’enregistrement|Aufnahme starten|Iniciar grabación
    输入|入力|입력|Entrée|Eingabe|Entrada
    翻译|翻訳|번역|Traduction|Übersetzung|Traducción
    设置|設定|설정|Réglages|Einstellungen|Ajustes
    设置…|設定…|설정…|Réglages…|Einstellungen…|Ajustes…
    正在停止识别…|認識を停止中…|인식 중지 중…|Arrêt de la reconnaissance…|Erkennung wird gestoppt…|Deteniendo reconocimiento…
    正在启动识别…|認識を開始中…|인식 시작 중…|Démarrage de la reconnaissance…|Erkennung wird gestartet…|Iniciando reconocimiento…
    正在下载并加载说话人模型…|話者モデルをダウンロード・読み込み中…|화자 모델 다운로드 및 로딩 중…|Téléchargement du modèle de locuteurs…|Sprechermodell wird geladen…|Descargando y cargando modelo de hablantes…
    翻译中…|翻訳中…|번역 중…|Traduction…|Übersetzung läuft…|Traduciendo…
    识别准备失败，请在设置中查看模型状态|認識の準備に失敗しました。設定でモデルを確認してください|인식 준비 실패. 설정에서 모델 상태를 확인하세요|Échec de préparation. Vérifiez le modèle dans les réglages.|Vorbereitung fehlgeschlagen. Modell in den Einstellungen prüfen.|No se pudo preparar el reconocimiento. Revisa el modelo en Ajustes.
    正在准备识别…|認識を準備中…|인식 준비 중…|Préparation de la reconnaissance…|Erkennung wird vorbereitet…|Preparando reconocimiento…
    等待语音…|音声を待っています…|음성 대기 중…|En attente de parole…|Warten auf Sprache…|Esperando voz…
    双击浮窗开始识别|ダブルクリックで字幕を開始|두 번 클릭하여 자막 시작|Double-cliquez pour démarrer|Doppelklicken zum Starten|Doble clic para iniciar
    显示内容|表示内容|표시 내용|Affichage|Anzeige|Mostrar
    原文字号|字幕の文字サイズ|자막 글자 크기|Taille des sous-titres|Untertitelgröße|Tamaño de subtítulos
    译文字号|翻訳の文字サイズ|번역 글자 크기|Taille de la traduction|Übersetzungsgröße|Tamaño de traducción
    悬浮窗|フローティングウィンドウ|플로팅 창|Fenêtre flottante|Schwebendes Fenster|Ventana flotante
    透明度|不透明度|불투명도|Opacité|Deckkraft|Opacidad
    无字幕时自动隐藏|字幕がないときに隠す|자막이 없으면 숨기기|Masquer en cas d’inactivité|Bei Inaktivität ausblenden|Ocultar si no hay actividad
    等待时间|待機時間|대기 시간|Délai d’inactivité|Wartezeit|Tiempo de espera
     分钟| 分| 분| min| Min.| min
    隐藏后仍会继续监听；识别到新的语音时，字幕窗会自动淡入。|非表示中も音声を認識し、新しい音声で字幕が再表示されます。|숨겨진 동안에도 듣기를 계속하며 새 음성을 인식하면 다시 표시됩니다.|L’écoute continue en arrière-plan. Une nouvelle parole réaffiche la fenêtre.|Die Erkennung läuft weiter. Bei neuer Sprache erscheint das Fenster wieder.|La escucha continúa en segundo plano. La ventana reaparece al detectar voz.
    直接拖动窗口可调整位置，拖动边缘可调整尺寸。|ウィンドウをドラッグして移動し、端をドラッグしてサイズを変更できます。|창을 드래그하여 이동하고 가장자리를 드래그하여 크기를 조절하세요.|Déplacez la fenêtre en la faisant glisser ; ses bords permettent de la redimensionner.|Fenster zum Verschieben ziehen; Ränder zum Ändern der Größe ziehen.|Arrastra la ventana para moverla y sus bordes para cambiar su tamaño.
    系统|システム|시스템|Système|System|Sistema
    在 Dock 与强制退出中显示|Dock と強制終了に表示|Dock 및 강제 종료에 표시|Afficher dans le Dock et Forcer à quitter|Im Dock und unter Sofort beenden anzeigen|Mostrar en Dock y Forzar salida
    关闭时仅保留顶部菜单栏图标；开启后可在系统的强制退出窗口中找到 LiveCaption。|オフの場合はメニューバーのみに表示します。オンにすると強制終了画面にも表示します。|끄면 메뉴 막대에만 표시됩니다. 켜면 강제 종료 창에서도 찾을 수 있습니다.|Sinon, seule l’icône de la barre des menus reste visible. Cette option permet de forcer la fermeture.|Wenn deaktiviert, bleibt nur das Menüleistensymbol. Aktivieren ermöglicht die Anzeige unter Sofort beenden.|Si está desactivado, solo queda el icono de la barra de menús. Actívalo para poder usar Forzar salida.
    音频|音声|오디오|Audio|Audio|Audio
    翻译语言包|翻訳言語パック|번역 언어 팩|Packs de traduction|Übersetzungspakete|Paquetes de traducción
    需要下载|ダウンロードが必要|다운로드 필요|Téléchargement requis|Download erforderlich|Descarga necesaria
    下载语言包|言語パックをダウンロード|언어 팩 다운로드|Télécharger le pack|Sprachpaket laden|Descargar paquete
    请在系统窗口中确认下载|システムのダイアログでダウンロードを確認してください|시스템 대화상자에서 다운로드를 확인하세요|Confirmez le téléchargement dans la boîte de dialogue système|Download im Systemdialog bestätigen|Confirma la descarga en el diálogo del sistema
    语言包由 macOS Translation 下载和管理；确认窗口会固定显示在设置窗口中。|言語パックは macOS Translation が管理します。確認画面は設定内に表示されます。|언어 팩은 macOS Translation이 관리하며 확인 대화상자는 설정에 표시됩니다.|Les packs sont gérés par macOS Translation. La confirmation apparaît dans les réglages.|macOS Translation verwaltet die Pakete. Die Bestätigung erscheint in den Einstellungen.|macOS Translation gestiona los paquetes. La confirmación aparece en Ajustes.
    录音|録音|녹음|Enregistrement|Aufnahme|Grabación
    按说话人断句|話者ごとに字幕を区切る|화자별 자막 구분|Séparer les sous-titres par locuteur|Untertitel nach Sprecher trennen|Separar subtítulos por hablante
    停止录音后自动生成总结|録音後に自動で要約|녹음 후 자동 요약|Résumer après l’enregistrement|Nach der Aufnahme zusammenfassen|Resumir al terminar la grabación
    总结方式|要約方法|요약 방식|Service de résumé|Zusammenfassungsdienst|Proveedor de resumen
    程序|実行ファイル|실행 파일|Exécutable|Programm|Ejecutable
    选择…|選択…|선택…|Choisir…|Auswählen…|Elegir…
    更换…|変更…|변경…|Modifier…|Ändern…|Cambiar…
    启动参数（可选）|起動引数（任意）|실행 인수 (선택)|Arguments (facultatif)|Argumente (optional)|Argumentos (opcional)
    应用会把总结要求和字幕文本通过标准输入交给该程序，并读取其标准输出作为总结。|要約の指示と字幕を標準入力で渡し、標準出力を要約として取得します。|요약 지침과 자막을 표준 입력으로 전달하고 표준 출력을 요약으로 사용합니다.|Les consignes et le texte sont transmis sur l’entrée standard ; la sortie standard fournit le résumé.|Anweisungen und Text werden über die Standardeingabe übergeben; die Standardausgabe liefert die Zusammenfassung.|Las instrucciones y el texto se envían a la entrada estándar; la salida estándar devuelve el resumen.
    保存位置|保存先|저장 위치|Emplacement|Speicherort|Ubicación
    选择“两者”时，电脑音频和麦克风会分别保存为两个 WAV 文件。CLI 只接收字幕文本，不接收音频；是否联网由所选 CLI 自身决定。|両方を選ぶと、システム音声とマイクは別々の WAV に保存されます。CLI には字幕のみを送り、通信の有無は CLI に依存します。|두 소스는 별도의 WAV 파일로 저장됩니다. CLI에는 자막만 전달하며 네트워크 사용은 해당 프로그램에 따릅니다.|Les deux sources sont enregistrées dans des WAV séparés. Le CLI reçoit uniquement le texte ; son accès au réseau dépend du programme.|Beide Quellen werden getrennt als WAV gespeichert. Das CLI erhält nur Text; die Netzwerknutzung bestimmt das gewählte Programm.|Las fuentes se guardan en WAV separados. El CLI solo recibe texto; el acceso a la red depende del programa.
    识别模型|認識モデル|인식 모델|Modèle de reconnaissance|Erkennungsmodell|Modelo de reconocimiento
    模型首次使用时下载，之后完全离线运行。高精度模型更准确，但占用更多内存。|モデルは初回にダウンロードし、その後はオフラインで動作します。高精度モデルはより多くのメモリを使います。|모델은 처음에 다운로드한 후 오프라인으로 작동합니다. 고정밀 모델은 메모리를 더 사용합니다.|Les modèles sont téléchargés au premier usage, puis fonctionnent hors ligne. Le modèle précis utilise plus de mémoire.|Modelle werden einmal geladen und laufen danach offline. Das genauere Modell benötigt mehr Arbeitsspeicher.|Los modelos se descargan una vez y después funcionan sin conexión. El modelo preciso usa más memoria.
    语言包已准备完成|言語パックの準備完了|언어 팩 준비 완료|Pack prêt|Sprachpaket bereit|Paquete listo
    打开录音文件夹|録音フォルダを開く|녹음 폴더 열기|Ouvrir le dossier des enregistrements|Aufnahmeordner öffnen|Abrir carpeta de grabaciones
    打开最近录音|最新の録音を開く|최근 녹음 열기|Ouvrir le dernier enregistrement|Letzte Aufnahme öffnen|Abrir última grabación
    隐藏字幕窗|字幕ウィンドウを隠す|자막 창 숨기기|Masquer les sous-titres|Untertitelfenster ausblenden|Ocultar ventana de subtítulos
    显示字幕窗|字幕ウィンドウを表示|자막 창 표시|Afficher les sous-titres|Untertitelfenster anzeigen|Mostrar ventana de subtítulos
    电脑音频|システム音声|시스템 오디오|Audio système|Systemaudio|Audio del sistema
    麦克风|マイク|마이크|Microphone|Mikrofon|Micrófono
    两者|両方|둘 다|Les deux|Beide|Ambos
    仅字幕|字幕のみ|자막만|Sous-titres seuls|Nur Untertitel|Solo subtítulos
    字幕＋翻译|字幕＋翻訳|자막 + 번역|Sous-titres + traduction|Untertitel + Übersetzung|Subtítulos + traducción
    仅翻译|翻訳のみ|번역만|Traduction seule|Nur Übersetzung|Solo traducción
    本机智能|オンデバイス|온디바이스|Sur l’appareil|Auf dem Gerät|En el dispositivo
    自定义 CLI|カスタム CLI|사용자 지정 CLI|CLI personnalisé|Eigenes CLI|CLI personalizado
    简体中文|簡体字中国語|중국어 간체|Chinois simplifié|Chinesisch (vereinfacht)|Chino simplificado
    平衡 · 181 MB|バランス · 181 MB|균형 · 181 MB|Équilibré · 181 MB|Ausgewogen · 181 MB|Equilibrado · 181 MB
    高精度 · 547 MB|高精度 · 547 MB|고정밀 · 547 MB|Haute précision · 547 MB|Hohe Genauigkeit · 547 MB|Alta precisión · 547 MB
    选择录音和文本的保存位置|録音とテキストの保存先を選択|녹음 및 텍스트 저장 위치 선택|Choisir le dossier des enregistrements et textes|Speicherort für Aufnahmen und Texte wählen|Elegir ubicación para grabaciones y textos
    选择用于总结的命令行程序|要約用のコマンドラインプログラムを選択|요약용 명령줄 프로그램 선택|Choisir un programme de résumé|Programm für Zusammenfassungen wählen|Elegir programa de resumen
    选择|選択|선택|Choisir|Auswählen|Elegir
    暂时无法确定原文语言|元の言語をまだ判定できません|원문 언어를 아직 확인할 수 없습니다|Langue source encore inconnue|Quellsprache noch unbekannt|Idioma de origen aún desconocido
    系统不支持该语言的翻译|この言語の翻訳はサポートされていません|이 언어의 번역은 지원되지 않습니다|Traduction non prise en charge|Übersetzung für diese Sprache nicht unterstützt|Traducción no compatible con este idioma
    无法确认翻译语言包状态|言語パックの状態を確認できません|언어 팩 상태를 확인할 수 없습니다|Impossible de vérifier le pack|Sprachpaketstatus nicht abrufbar|No se pudo verificar el paquete
    缺少录音权限，请在系统设置的隐私与安全性中授权。|録音権限が必要です。システム設定のプライバシーとセキュリティで許可してください。|녹음 권한이 필요합니다. 시스템 설정의 개인정보 보호 및 보안에서 허용하세요.|Autorisez l’enregistrement dans Réglages Système > Confidentialité et sécurité.|Aufnahmeberechtigung in Systemeinstellungen > Datenschutz & Sicherheit erteilen.|Autoriza la grabación en Ajustes del Sistema > Privacidad y seguridad.
    没有找到可采集的显示器。|キャプチャ可能なディスプレイがありません。|캡처할 디스플레이가 없습니다.|Aucun écran disponible.|Kein Bildschirm verfügbar.|No hay pantalla disponible.
    使用 Apple 本机智能模型；不可用时自动生成基础总结。|Apple のオンデバイスモデルを使用し、利用できない場合は基本的な要約を作成します。|Apple 온디바이스 모델을 사용하며 사용할 수 없으면 기본 요약을 생성합니다.|Utilise le modèle local Apple, ou un résumé basique s’il est indisponible.|Verwendet Apples lokales Modell, sonst eine einfache Zusammenfassung.|Usa el modelo local de Apple o un resumen básico si no está disponible.
    请选择一个命令行程序。|コマンドラインプログラムを選択してください。|명령줄 프로그램을 선택하세요.|Choisissez un programme en ligne de commande.|Bitte ein Kommandozeilenprogramm wählen.|Elige un programa de línea de comandos.
    已连接自定义 CLI；其联网和数据处理方式由该程序决定。|カスタム CLI に接続しました。通信とデータ処理はそのプログラムに依存します。|사용자 지정 CLI가 연결되었습니다. 네트워크와 데이터 처리는 해당 프로그램에 따릅니다.|CLI connecté. Le programme contrôle le réseau et le traitement des données.|Eigenes CLI verbunden. Es bestimmt Netzwerkzugriff und Datenverarbeitung.|CLI conectado. El programa controla la red y el tratamiento de datos.
    所选文件无法执行，使用时会自动回退到本机总结。|このファイルは実行できません。ローカルの要約を使用します。|실행할 수 없는 파일입니다. 로컬 요약을 사용합니다.|Fichier non exécutable. Le résumé local sera utilisé.|Datei nicht ausführbar. Lokale Zusammenfassung wird verwendet.|Archivo no ejecutable. Se usará el resumen local.
    模型尚未下载，点击开始后自动下载|モデル未取得。開始するとダウンロードします|모델 없음. 시작하면 다운로드합니다|Modèle absent ; démarrez pour télécharger|Modell fehlt; zum Laden starten|Modelo ausente; inicia para descargar
    模型已下载，点击开始加载|モデル取得済み。開始すると読み込みます|다운로드 완료. 시작하면 로드합니다|Modèle téléchargé ; démarrez pour charger|Modell heruntergeladen; zum Laden starten|Modelo descargado; inicia para cargar
    正在下载 Whisper 模型…|Whisper モデルをダウンロード中…|Whisper 모델 다운로드 중…|Téléchargement du modèle Whisper…|Whisper-Modell wird heruntergeladen…|Descargando modelo Whisper…
    正在加载 Whisper…|Whisper を読み込み中…|Whisper 로딩 중…|Chargement de Whisper…|Whisper wird geladen…|Cargando Whisper…
    Whisper 已就绪|Whisper 準備完了|Whisper 준비 완료|Whisper prêt|Whisper bereit|Whisper listo
    模型无法加载|モデルを読み込めません|모델 로드 실패|Chargement du modèle impossible|Modell kann nicht geladen werden|No se pudo cargar el modelo
    Whisper 推理失败|Whisper の推論に失敗|Whisper 추론 실패|Échec de l’inférence Whisper|Whisper-Inferenz fehlgeschlagen|Error de inferencia de Whisper
    当前下载源不支持断点续传|この配信元はダウンロード再開に対応していません|이 다운로드 소스는 이어받기를 지원하지 않습니다|Cette source ne permet pas la reprise|Diese Quelle unterstützt kein Fortsetzen|Esta fuente no permite reanudar
    模型校验失败，已清除损坏下载，请重试|検証に失敗しました。破損ファイルを削除しました。再試行してください|모델 검증 실패. 손상된 파일을 삭제했습니다. 다시 시도하세요|Vérification échouée. Fichier corrompu supprimé ; réessayez|Prüfung fehlgeschlagen. Defekte Datei entfernt; erneut versuchen|Verificación fallida. Archivo dañado eliminado; reintenta
    需要在设置中下载翻译语言包|設定で翻訳言語パックをダウンロードしてください|설정에서 번역 언어 팩을 다운로드하세요|Téléchargez le pack dans les réglages|Sprachpaket in den Einstellungen laden|Descarga el paquete en Ajustes
    正在续传|再開中|이어받는 중|Reprise|Wird fortgesetzt|Reanudando
    正在下载|ダウンロード中|다운로드 중|Téléchargement|Download läuft|Descargando
    正在连接并下载|接続・ダウンロード中|연결 및 다운로드 중|Connexion et téléchargement|Verbindung und Download|Conectando y descargando
     已就绪| 準備完了| 준비 완료| prêt| bereit| listo
     已下载，点击开始加载| 取得済み。開始して読み込み| 다운로드 완료. 시작하여 로드| téléchargé ; démarrer pour charger| heruntergeladen; zum Laden starten| descargado; inicia para cargar
     已保存 | 保存済み | 저장됨 | enregistré : | gespeichert: | guardado:\u{20}
    ，点击开始继续下载|。開始してダウンロード再開|. 시작하여 이어받기| ; démarrer pour reprendre|; zum Fortsetzen starten|; inicia para reanudar
     尚未下载，点击开始后自动下载| 未取得。開始してダウンロード| 다운로드 안 됨. 시작하여 다운로드| absent ; démarrer pour télécharger| fehlt; zum Herunterladen starten| ausente; inicia para descargar
    Whisper 错误：|Whisper エラー：|Whisper 오류: |Erreur Whisper : |Whisper-Fehler: |Error de Whisper:\u{20}
    模型下载暂停：|モデルのダウンロードを一時停止：|모델 다운로드 일시 정지: |Téléchargement suspendu : |Modelldownload pausiert: |Descarga pausada:\u{20}
    ；已保留 |；保存済み |; 저장됨 | ; conservé : |; gespeichert: |; guardado:\u{20}
    ，再次点击开始会继续|。開始を押すと再開します|. 시작을 누르면 이어받습니다| ; démarrer pour reprendre|; zum Fortsetzen erneut starten|; vuelve a iniciar para reanudar
    下载未完成：|ダウンロード未完了：|다운로드 미완료: |Téléchargement incomplet : |Download unvollständig: |Descarga incompleta:\u{20}
    翻译失败：|翻訳に失敗：|번역 실패: |Échec de traduction : |Übersetzung fehlgeschlagen: |Error de traducción:\u{20}
    语言包下载失败：|言語パックのダウンロード失敗：|언어 팩 다운로드 실패: |Échec du pack : |Sprachpaket-Download fehlgeschlagen: |Error al descargar el paquete:\u{20}
    输入来源：|音声入力：|오디오 소스: |Source audio : |Audioquelle: |Fuente de audio:\u{20}
    切换录音来源失败：|録音入力の切替失敗：|녹음 소스 전환 실패: |Échec du changement de source : |Wechsel der Aufnahmequelle fehlgeschlagen: |Error al cambiar la fuente:\u{20}
    文本保存失败：|テキスト保存失敗：|텍스트 저장 실패: |Échec de sauvegarde du texte : |Textspeicherung fehlgeschlagen: |Error al guardar texto:\u{20}
    录音写入失败：|録音の書き込み失敗：|녹음 저장 실패: |Échec d’écriture audio : |Audiospeicherung fehlgeschlagen: |Error al guardar audio:\u{20}
    。已识别文本仍会保存。|。認識済みのテキストは保存されます。|. 인식된 텍스트는 저장됩니다.|. Le texte reconnu sera sauvegardé.|. Erkannter Text wird weiterhin gespeichert.|. El texto reconocido se guardará.
    字幕自动保存失败：|字幕の自動保存失敗：|자막 자동 저장 실패: |Échec de sauvegarde automatique : |Automatisches Speichern fehlgeschlagen: |Error de guardado automático:\u{20}
    说话人模型加载失败：|話者モデル読み込み失敗：|화자 모델 로드 실패: |Échec du modèle de locuteurs : |Sprechermodell konnte nicht geladen werden: |Error al cargar modelo de hablantes:\u{20}
    说话人识别失败：|話者識別失敗：|화자 식별 실패: |Échec d’identification : |Sprechererkennung fehlgeschlagen: |Error de identificación:\u{20}
    失败|失敗|실패|Échec|Fehlgeschlagen|Error
    已检测到 |検出済み：|감지됨: |Détecté : |Erkannt: |Detectado:\u{20}
    。总结时会联网发送字幕文本，不发送音频。|。要約時に字幕をオンラインで送信します。音声は送信しません。|. 요약 시 자막만 온라인으로 전송하며 오디오는 전송하지 않습니다.|. Le résumé envoie le texte en ligne, pas l’audio.|. Für die Zusammenfassung wird Text online gesendet, kein Audio.|. El resumen envía texto en línea, no audio.
    未检测到 |未検出：|찾을 수 없음: |Introuvable : |Nicht gefunden: |No encontrado:\u{20}
    ，使用时会自动回退到本机总结。|。ローカルの要約に切り替えます。|. 로컬 요약을 사용합니다.| ; le résumé local sera utilisé.|; lokale Zusammenfassung wird verwendet.|; se usará el resumen local.
    """
}
