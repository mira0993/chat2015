template <class T>
class NodeList {
	public:
		NodeList<T>* get_prev();
		NodeList<T>* get_next();
		T* get_element();
		void set_element(T *element);
		void set_prev(NodeList *prev);
		void set_next(NodeList *next);
		
	private:
		T *element;
		NodeList<T> *prev, *next;
};

template <class T>
class Lista {

	public:
		Lista();
		~Lista();
		void append(T *element);
		T* get_removing();

	private:
		NodeList<T> *root, *end;
		int count;
};

template <class T>
NodeList<T>* NodeList<T>::get_prev() {
	return this->prev;
}

template <class T>
NodeList<T>* NodeList<T>::get_next() {
	return this->next;
}

template <class T>
T* NodeList<T>::get_element() {
	return this->element;
}

template <class T>
void NodeList<T>::set_element(T *element) {
	this->element = element;
}

template <class T>
void NodeList<T>::set_prev(NodeList *prev) {
	this->prev = prev;
}

template <class T>
void NodeList<T>::set_next(NodeList *next) {
	this->next = next;
}

template <class T>
Lista<T>::Lista() {
	this->root = 0;
	this->end = 0;
	this->count = 0;
}

template <class T>
Lista<T>::~Lista() {
	while (this->root) {
		NodeList<T> *tmp = this->root;
		this->root = this->root->get_next();
		delete tmp;
	}
}

template <class T>
void Lista<T>::append(T *element) {
	NodeList<T> *tmp = new NodeList<T>;
	if (this->count == 0) 
		this->root = tmp;
	else {
		this->end->set_next(tmp);
		tmp->set_prev(this->end);
	}
	tmp->set_element(element);
	tmp->set_next(0);
	this->end = tmp;
	this->count++;
}

template <class T>
T* Lista<T>::get_removing() {
	this->count--;
	NodeList<T> *tmp = this->root;
	this->root = this->root->get_next();
	if (this->count > 0)
		this->root->set_prev(0);
	return tmp->get_element();
}