// User-facing strings for the webview. English is the key; Brazilian Portuguese is used when Rust
// reports a Portuguese system locale (see `src-tauri/src/i18n.rs`).

let portuguese = false;

export function setLocale(locale: string): void {
  portuguese = locale.toLowerCase().startsWith("pt");
  document.documentElement.lang = portuguese ? "pt-BR" : "en";
}

/** Translates `english` and fills `{name}` placeholders from `values`. */
export function t(english: string, values: Record<string, string | number> = {}): string {
  const text = (portuguese && PT_BR[english]) || english;
  return text.replace(/\{(\w+)\}/g, (match, name: string) => (name in values ? String(values[name]) : match));
}

export function formatDate(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleDateString(portuguese ? "pt-BR" : "en-US", { year: "numeric", month: "short", day: "numeric" });
}

export const PT_BR: Record<string, string> = {

  // Onboarding
  "Welcome to Feather": "Bem-vindo ao Feather",
  "Press a shortcut anywhere. Feather reads what is on your screen, writes a reply, and pastes it into the field you are typing in.":
    "Aperte um atalho em qualquer lugar. O Feather lê o que está na sua tela, escreve uma resposta e cola no campo em que você está digitando.",
  "Get Started": "Começar",
  Continue: "Continuar",
  Back: "Voltar",
  Finish: "Concluir",
  "Step {current} of {total}": "Etapa {current} de {total}",
  "Connect a provider": "Conecte um provedor",
  "Connect a provider to continue.": "Conecte um provedor para continuar.",
  "Choose how Feather gets its replies. You can change this later in Settings.":
    "Escolha como o Feather obtém as respostas. Você pode mudar isso depois nas Configurações.",
  "Try it out": "Experimente",
  "Click the box below, then press {shortcut}. Say what you want, and Feather writes it here.":
    "Clique na caixa abaixo e aperte {shortcut}. Diga o que você quer e o Feather escreve aqui.",
  "Your reply appears here": "Sua resposta aparece aqui",
  "Show Welcome Guide…": "Mostrar guia de boas-vindas…",
  // Panel
  "What do you want to write?": "O que você quer escrever?",
  "Refine: shorter, more formal…": "Refine: mais curto, mais formal…",
  "Generating…": "Gerando…",
  Cancel: "Cancelar",
  "Partial window": "Janela parcial",
  "This window is too large to read whole, so Feather read only part of it": "Esta janela é grande demais para ler inteira, então o Feather leu só uma parte",
  "Text selected": "Texto selecionado",
  "Typing in a field": "Digitando em um campo",
  "Feather opened while you were typing; Insert writes the reply in that field": "O Feather abriu enquanto você digitava; Inserir escreve a resposta nesse campo",
  Window: "Janela",
  "Feather sees the text you selected": "O Feather vê o texto que você selecionou",
  "Feather is reading the window you are in": "O Feather está lendo a janela em que você está",
  "Feather knows which app you are in": "O Feather sabe em qual app você está",
  "No app context": "Sem contexto de app",
  "Reading window…": "Lendo a janela…",
  "Capturing window…": "Capturando janela…",
  Copy: "Copiar",
  Retry: "Refazer",
  New: "Nova",
  Insert: "Inserir",
  Generate: "Gerar",
  "Previous conversation {current} of {total}": "Conversa anterior {current} de {total}",
  Refine: "Refinar",
  Recent: "Recentes",
  "Insert into {app}": "Inserir em {app}",
  Screenshot: "Captura de tela",
  "Feather sends a picture of the window with your request": "O Feather envia uma imagem da janela junto com o seu pedido",
  "{count} captures": "{count} capturas",
  "You pressed the shortcut more than once in this app, so Feather combined what it read each time.":
    "Você apertou o atalho mais de uma vez neste app, então o Feather juntou o que leu em cada vez.",
  "Reply ready.": "Resposta pronta.",
  "Connect a provider in Settings so Feather can write for you.": "Conecte um provedor nas Configurações para o Feather escrever por você.",
  "Open Settings": "Abrir Configurações",

  // Settings
  "Feather Settings": "Configurações do Feather",
  General: "Geral",
  Connection: "Conexão",
  "No API key, and it also answers questions. Paid plan.": "Sem chave de API, e também responde perguntas. Plano pago.",
  "Paste an OpenCode Go API key. Free.": "Cole uma chave de API do OpenCode Go. Grátis.",
  "Monthly plan": "Plano mensal",
  "Yearly plan": "Plano anual",
  "No plan yet": "Ainda sem plano",
  "Set Up…": "Configurar…",
  "In use": "Em uso",
  Use: "Usar",
  "Remove Key": "Remover chave",
  "Free plan": "Plano grátis",
  Claude: "Claude",
  "Paste an Anthropic API key from the Console.": "Cole uma chave de API da Anthropic, do Console.",
  "Use your own OpenAI, Claude, or OpenCode Go API key. Keys are stored in your system's secure credential storage.":
    "Use a sua própria chave de API da OpenAI, do Claude ou do OpenCode Go. As chaves ficam no armazenamento seguro do sistema.",
  "Paste an OpenAI API key from the Platform.": "Cole uma chave de API da OpenAI, criada na Platform.",
  OpenAI: "OpenAI",
  "Answers your questions": "Responde às suas perguntas",
  "No API key to manage": "Sem chave de API para gerenciar",
  "$4 a month or $36 a year": "US$ 4 por mês ou US$ 36 por ano",
  "Use Feather Plus for replies?": "Usar o Feather Plus nas respostas?",
  "Feather is using {provider} now. You can switch again in Settings > Connection anytime.":
    "O Feather está usando o {provider}. Você pode trocar de novo em Ajustes > Conexão quando quiser.",
  "Keep {provider}": "Manter o {provider}",
  "Use Feather Plus": "Usar o Feather Plus",
  "Feather Plus": "Feather Plus",
  System: "Sistema",
  "Needs attention": "Requer atenção",
  "Quit Feather": "Encerrar o Feather",
  Shortcut: "Atalho",
  "Open Feather": "Abrir o Feather",
  "Another app is using this shortcut. Choose a different one.": "Outro app está usando este atalho. Escolha outro.",
  Startup: "Inicialização",
  "Open Feather at login": "Abrir o Feather ao ligar o computador",
  "Starts Feather in the background when you sign in to your computer.":
    "Inicia o Feather em segundo plano quando você entra no computador.",
  Context: "Contexto",
  "Include a screenshot of the active window": "Incluir uma captura da janela ativa",
  "Gives the model visual context.": "Dá contexto visual ao modelo.",
  "Nothing is captured until you press the shortcut, and the context is discarded when the panel closes.":
    "Nada é capturado até você pressionar o atalho, e o contexto é descartado quando o painel fecha.",
  Instructions: "Instruções",
  "Feather follows these in every reply. Write your own or add a suggestion.":
    "O Feather segue estas instruções em todas as respostas. Escreva as suas ou adicione uma sugestão.",
  "For example: Write in a friendly tone and keep replies short.": "Por exemplo: Escreva em tom amigável e mantenha as respostas curtas.",
  "No emojis": "Sem emojis",
  "Do not use emojis.": "Não use emojis.",
  "No em dashes": "Sem travessões",
  "Do not use em dashes.": "Não use travessões.",
  "Keep it short": "Seja breve",
  "Keep replies short and to the point.": "Mantenha as respostas curtas e diretas.",
  "Friendly tone": "Tom amigável",
  "Write in a warm, friendly tone.": "Escreva em um tom caloroso e amigável.",
  About: "Sobre",
  Version: "Versão",
  "Check for Updates…": "Procurar Atualizações…",
  "OpenCode Go": "OpenCode Go",
  Account: "Conta",
  Upgrade: "Fazer upgrade",
  Replies: "Respostas",
  Natural: "Natural",
  Friendly: "Amigável",
  Professional: "Profissional",
  Casual: "Descontraído",
  "Match the request": "Conforme o pedido",
  Short: "Curta",
  Detailed: "Detalhada",
  "Same as the conversation": "O mesmo da conversa",
  English: "Inglês",
  Portuguese: "Português",
  Tone: "Tom",
  Length: "Tamanho",
  Language: "Idioma",
  Style: "Estilo",
  "Applies to every reply. Your instructions above can refine it.": "Vale para todas as respostas. Suas instruções acima podem ajustar.",
  Model: "Modelo",
  "Couldn't load the models. Check your key and connection.":
    "Não foi possível carregar os modelos. Verifique sua chave e a conexão.",
  "API key": "Chave de API",
  "Paste your key": "Cole sua chave",
  Save: "Salvar",
  "Replace…": "Substituir…",
  Refresh: "Atualizar",
  Connected: "Conectado",
  "Sign-in continues in your browser.": "O login continua no seu navegador.",
  "Signed in": "Conectado",
  "Manage…": "Gerenciar…",
  More: "Mais",
  "Sign in…": "Entrar…",
  "Not signed in": "Não conectado",
  "Sign in to see your plan and usage.": "Entre para ver seu plano e uso.",
  "See Feather Plus plans on the website": "Ver os planos do Feather Plus no site",
  "Plus Monthly": "Plus Mensal",
  "Plus Yearly": "Plus Anual",
  Answer: "Resposta",
  "Suggested text": "Texto sugerido",
  "To get answers to your questions while Feather writes, subscribe to Feather Plus.":
    "Para responder perguntas e dúvidas enquanto gera texto, assine o Feather Plus.",
  "Sign in": "Entrar",
  Email: "E-mail",
  Plan: "Plano",
  "No plan": "Sem plano",
  "Choose a plan…": "Escolher um plano…",
  "Manage subscription…": "Gerenciar assinatura…",
  "Sign out": "Sair",
  "Resets on {date}.": "Renova em {date}.",
  "This month's allowance": "Franquia deste mês",
  "{percent}% used": "{percent}% usado",
  "What Feather can do here": "O que o Feather consegue fazer aqui",
  "Read the context around your cursor": "Ler o contexto ao redor do cursor",
  "Reads the focused field, the selection, and the window's text through accessibility.":
    "Lê o campo em foco, a seleção e o texto da janela pela acessibilidade.",
  "Capture the active window": "Capturar a janela ativa",
  "Attaches a screenshot of the window you were using.": "Anexa uma captura de tela da janela que você estava usando.",
  "Paste replies": "Colar as respostas",
  "Pastes the reply into the field you were typing in.": "Cola a resposta no campo em que você estava digitando.",
  "Available": "Disponível",
  "Unavailable": "Indisponível",
  "Feather is running in a Wayland session. Wayland does not let apps look at or type into other windows, so Feather reads the app in front through accessibility and copies each reply for you to paste.":
    "O Feather está rodando em uma sessão Wayland. O Wayland não permite que um app olhe outras janelas nem digite nelas, então o Feather lê o app em primeiro plano pela acessibilidade e copia cada resposta para você colar.",
  "Some apps only share their text when assistive technologies are enabled. If context is missing, turn on accessibility support in your desktop settings.":
    "Alguns apps só compartilham o texto quando as tecnologias assistivas estão ativadas. Se faltar contexto, ative o suporte de acessibilidade nas configurações do seu ambiente de trabalho.",
  "Wayland does not let apps listen for a global shortcut. In your desktop's keyboard settings, add a shortcut that runs Feather with the --prompt option, or open Feather from its tray menu.":
    "O Wayland não permite que apps escutem um atalho global. Nas configurações de teclado do seu ambiente de trabalho, adicione um atalho que execute o Feather com a opção --prompt, ou abra o Feather pelo menu da bandeja.",
  "Click the box below, then open Feather from its tray menu or your own shortcut. Say what you want, and Feather writes it here.":
    "Clique na caixa abaixo e abra o Feather pelo menu da bandeja ou pelo seu próprio atalho. Diga o que você quer, e o Feather escreve aqui.",
  "Windows needs no extra permissions. Apps that run as administrator cannot be read or pasted into unless Feather also runs as administrator.":
    "O Windows não precisa de permissões extras. Apps que rodam como administrador não podem ser lidos nem receber texto colado, a menos que o Feather também rode como administrador.",

  // Feedback
  "Send Feedback": "Enviar feedback",
  "Tell us what works, what doesn't, or what you'd like Feather to do.":
    "Conte o que funciona, o que não funciona ou o que você gostaria que o Feather fizesse.",
  "Your feedback": "Seu feedback",
  "Email (optional)": "E-mail (opcional)",
  "Only if you'd like a reply.": "Só se quiser uma resposta.",
  "Sends your message and the Feather and system versions. Nothing from your screen.":
    "Envia sua mensagem e as versões do Feather e do sistema. Nada da sua tela.",
  Send: "Enviar",
  "Keep your message under 5,000 characters.": "Mantenha sua mensagem com menos de 5.000 caracteres.",
  "Thanks for your feedback!": "Obrigado pelo feedback!",
  "It goes straight to the people who build Feather.": "Ele vai direto para quem faz o Feather.",
  Done: "OK",
};
