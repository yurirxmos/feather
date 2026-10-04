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
  // Panel
  "What do you want to write?": "O que você quer escrever?",
  "Refine: shorter, more formal…": "Refine: mais curto, mais formal…",
  "Generating…": "Gerando…",
  Cancel: "Cancelar",
  "Partial context": "Contexto parcial",
  "Text selected": "Texto selecionado",
  "Focused text": "Texto em foco",
  "No app context": "Sem contexto de app",
  "Reading screen…": "Lendo a tela…",
  "Capturing window…": "Capturando janela…",
  Copy: "Copiar",
  Retry: "Refazer",
  Insert: "Inserir",
  Generate: "Gerar",

  // Settings
  "Feather Settings": "Configurações do Feather",
  General: "Geral",
  Connection: "Conexão",
  "No API key, and it also answers questions. Paid plan.": "Sem chave de API, e também responde perguntas. Plano pago.",
  "Sign in with your ChatGPT account. Free.": "Entre com a sua conta do ChatGPT. Grátis.",
  "Paste an OpenCode Go API key. Free.": "Cole uma chave de API do OpenCode Go. Grátis.",
  "Starter plan": "Plano Starter",
  "Max plan": "Plano Max",
  "No plan yet": "Ainda sem plano",
  "Set Up…": "Configurar…",
  "In use": "Em uso",
  Use: "Usar",
  "Remove Key": "Remover chave",
  "Free plan": "Plano grátis",
  "Use your own ChatGPT account or OpenCode Go key. Credentials are stored in your system's secure credential storage.":
    "Use a sua própria conta do ChatGPT ou chave do OpenCode Go. As credenciais ficam no armazenamento seguro do sistema.",
  "Answers your questions": "Responde às suas perguntas",
  "No API key to manage": "Sem chave de API para gerenciar",
  "Starter or Max plan": "Plano Starter ou Max",
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
  Context: "Contexto",
  "Include a screenshot of the active window": "Incluir uma captura da janela ativa",
  "Gives the model visual context.": "Dá contexto visual ao modelo.",
  "Nothing is captured until you press the shortcut, and the context is discarded when the panel closes.":
    "Nada é capturado até você pressionar o atalho, e o contexto é descartado quando o painel fecha.",
  Instructions: "Instruções",
  "Set writing preferences for every response, such as “Do not use emojis or em dashes.”":
    "Defina preferências de escrita para todas as respostas, como “Não use emojis nem travessões.”",
  About: "Sobre",
  Version: "Versão",
  "Check for Updates…": "Procurar Atualizações…",
  "OpenCode Go": "OpenCode Go",
  ChatGPT: "ChatGPT",
  Account: "Conta",
  Model: "Modelo",
  "Couldn't load the models. Check your key and connection.":
    "Não foi possível carregar os modelos. Verifique sua chave e a conexão.",
  "API key": "Chave de API",
  "Paste your key": "Cole sua chave",
  Save: "Salvar",
  "Replace…": "Substituir…",
  Refresh: "Atualizar",
  Connected: "Conectado",
  Disconnect: "Desconectar",
  "Signing in…": "Entrando…",
  "Sign in with ChatGPT": "Entrar com ChatGPT",
  "Sign-in continues in your browser.": "O login continua no seu navegador.",
  "Signed in": "Conectado",
  "Manage…": "Gerenciar…",
  "Sign in…": "Entrar…",
  "Sign in to Feather Plus": "Entrar no Feather Plus",
  "Use your Feather Plus account.": "Use a sua conta do Feather Plus.",
  Starter: "Starter",
  Max: "Max",
  Answer: "Resposta",
  "Suggested text": "Texto sugerido",
  "Sign in": "Entrar",
  Email: "E-mail",
  Plan: "Plano",
  "No plan": "Sem plano",
  "Choose a plan…": "Escolher um plano…",
  "Manage subscription…": "Gerenciar assinatura…",
  "Sign out": "Sair",
  "Usage this period": "Uso neste período",
  "Resets on {date}.": "Renova em {date}.",
  Requests: "Requisições",
  "{used} of {limit}": "{used} de {limit}",
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
  "Windows needs no extra permissions. Apps that run as administrator cannot be read or pasted into unless Feather also runs as administrator.":
    "O Windows não precisa de permissões extras. Apps que rodam como administrador não podem ser lidos nem receber texto colado, a menos que o Feather também rode como administrador.",
};
