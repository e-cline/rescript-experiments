// A ReScript-authored component, consumed exactly like any other TSX
// component -- normal import, normal JSX usage, normal types. The CSS
// Modules stylesheet it uses isn't wired up automatically (see
// @e-cline/react_ui_example's README), so it's imported explicitly here.
import {Greeting} from '@e-cline/react_ui_example/index';
import {createRoot} from 'react-dom/client';

import '@e-cline/react_ui_example/Greeting.css';

const container = document.getElementById('app');
if (!container) {
  throw new Error('#app not found');
}

createRoot(container).render(<Greeting name="ReScript" />);
