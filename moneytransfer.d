import std.stdio; 
import std.conv; 
import std.container;

// To avoid undeterministic destruction, Contexts always have to be instantiated on the callstack using 'scope' -- Contexts form hierarchies, so they have to be destroyed in the reverse order
class Context 
{
	this()
	{
		id_ = idCounter_++;
		parentContext_ = currentContext_;
		currentContext_ = this;
		writeln("Context.this(): id= ", id_, " | parentContext_=", parentContext_ is null ? "none" : to!string(parentContext_.id_)); // for testing
	}

	~this()
	{
		writeln("Context.this()~: id= ", id_, " | parentContext_=", parentContext_ is null ? "none" : to!string(parentContext_.id_));
		currentContext_ = parentContext_;
		idCounter_--; // for testing
	}

	static Context currentContext_;
	private Context parentContext_;
	int id_; // for testing
	static int idCounter_ = 0; // for testing
}

struct Money
{
	this(double v) { val = v; }
	double val;
}

interface MoneySource
{
	void transferTo(Money amount);
	void decreaseBalance(Money amount);
	void payBills();
}

interface MoneySink
{
	void increaseBalance(Money amount);
}

mixin template TransferMoneySource(ConcreteDerived)
{
	// Role behaviors
	void payBills()
	{
		writeln("TransferMoneySource.payBills()");
		// While object contexts are changing, we don't want to have an open iterator on an external object. Make a local copy.
		auto creditorsCopy = creditors();
		foreach (creditor; creditorsCopy)
		{
			writeln("TransferMoneySource.payBills() for creditor=", creditor);
			// Note that here we invoke another Use Case
			Money amount = creditor.amountOwed();
			auto source = self();
			auto destination = creditor.account();
			scope TransferMoneyContext transferTheFunds = new TransferMoneyContext(source, destination, amount);
			transferTheFunds.doIt();
			writeln("TransferMoneySource.payBills() for creditor=", creditor, " done");
		}
	}

	void transferTo(Money amount)
	{
		writeln("TransferMoneySource.transferTo()");
		// This code is reviewable and meaningfully testable with stubs!

		begin_transaction();
		scope(exit) end_transaction();

		auto self = self();
		if (self.availableBalance().val < amount.val)
		{
			throw new Exception("Insufficient funds");
		}
		else
		{
			self.decreaseBalance(amount);
			receipient().increaseBalance(amount);
			// self->updateLog("Transfer Out", MyTime(), amount);
			//	receipient()->updateLog("Transfer In", MyTime(), amount);
		}
		writeln("TransferMoneySource.transferTo() end");
	}

	// Helpers
	private ConcreteDerived self()
	{
		return cast(ConcreteDerived) this;
	}

	private MoneySink receipient()
	{
		writeln("MoneySink::receipient() Context.currentContext_=", Context.currentContext_);
		auto r = cast(TransferMoneyContext) Context.currentContext_;
		writeln("MoneySink::receipient() Context.currentContext_=", r);
		return r.destinationAccount();
	}

	private Array!Creditor creditors()
	{
		auto c = cast(PayBillsContext) Context.currentContext_;
		return c.creditors();
	}	
}

mixin template TransferMoneySink(ConcreteDerived)
{
	void transferFrom(Money amount)
	{
		writeln("TransferMoneySink::transferFrom()");
		self().increaseBalance(amount);
		// self().updateLog("Transfer in", std::time(nullptr), amount);
		writeln("TransferMoneySink::transferFrom()");
	}

	private ConcreteDerived self() { return cast(ConcreteDerived) this; }
}

abstract class Account
{
	this() { id = 42; }

	private immutable int id;
}

class InvestmentAccount : Account, MoneySource
{
	mixin TransferMoneySource!InvestmentAccount;

	this() 
	{ 
		availableBalance_ = Money(0); 
	}

	Money availableBalance()
	{
		return availableBalance_;
	}

	override void decreaseBalance(Money amount)
	{
		availableBalance_.val -= amount.val;
	}

	void increaseBalance(Money amount)
	{
		availableBalance_.val += amount.val;
	}

	// void updateLog(std::string, MyTime, Money);

	private Money availableBalance_;
}

class SavingsAccount : Account, MoneySink
{
	mixin TransferMoneySink!SavingsAccount;

	this() 
	{ 
		availableBalance_ = Money(0);
	}

	Money availableBalance()
	{
		return availableBalance_;
	}

	void decreaseBalance(Money m)
	{
		availableBalance_.val -= m.val;
	}

	void increaseBalance(Money m)
	{
		availableBalance_.val += m.val;
	}

	// void updateLog(std::string, MyTime, Money);

	private Money availableBalance_;
}

class CheckingAccount : Account, MoneySink
{
	mixin TransferMoneySink!SavingsAccount;

	this() 
	{ 
		availableBalance_ = Money(0);
	}

	Money availableBalance()
	{
		return availableBalance_;
	}

	void decreaseBalance(Money m)
	{
		availableBalance_.val -= m.val;
	}

	void increaseBalance(Money m)
	{
		availableBalance_.val += m.val;
	}

	// void updateLog(std::string, MyTime, Money);

	private Money availableBalance_;
}

interface Creditor
{
	MoneySink account();
	Money amountOwed();
}

class GasComponay : Creditor
{
	this()
	{
		account_ = new CheckingAccount();
	}

	MoneySink account()
	{
		return account_;
	}

	Money amountOwed()
	{
		return Money(15.00);
	}

	private MoneySink account_;
}

class ElectricCompany : Creditor
{
	this()
	{
		account_ = new SavingsAccount();
		account_.increaseBalance(Money(500.00));     // start off with a balance of 500
	}

	MoneySink account()
	{
		return account_;
	}

	Money amountOwed()
	{
		return Money(18.76);
	}

	private MoneySink account_;
}

class TransferMoneyContext : Context
{
	this(MoneySource sourceAccount, MoneySink destinationAccount, Money amount)
	{
		sourceAccount_ = sourceAccount;
		destinationAccount_ = destinationAccount;
		amount_ = amount;
	}

	void doIt()
	{
		writeln("TransferMoneyContext::doIt");
		auto s = sourceAccount();
		writeln("TransferMoneyContext::doIt &sourceAccount=", &s);
		auto a = amount();
		s.transferTo(a);
		writeln("TransferMoneyContext::doIt done");
	}

	Money amount()
	{
		return amount_;
	}

	MoneySource sourceAccount()
	{
		return sourceAccount_;
	}

	MoneySink destinationAccount()
	{
		return destinationAccount_;
	}

	private MoneySource sourceAccount_;
	private MoneySink destinationAccount_;
	private Money amount_;
}

class PayBillsContext : Context
{
	this(MoneySource sourceAccount, Array!Creditor creditors)
	{
		sourceAccount_ = sourceAccount;
		creditors_ = creditors;
	}

	void doIt()
	{
		writeln("PayBillsContext.payBills()");
		sourceAccount().payBills();
		writeln("PayBillsContext.payBills() done");
	}

	MoneySource sourceAccount()
	{
		return sourceAccount_;
	}

	Array!Creditor creditors()
	{
		return creditors_;
	}

	private MoneySource sourceAccount_; 
	private Array!Creditor creditors_;
}

void begin_transaction()
{
	writeln("begin_transaction");
}

void end_transaction()
{
	writeln("end_transaction");
}

void main() 
{
	writeln("main()");

	// use case 1
	{
		// source account
		auto investmentsAccount = new InvestmentAccount();
		investmentsAccount.increaseBalance(Money(100.00));       // prime it with some money
		writeln("main &investmentsAccount=", &investmentsAccount);

		// destination account
		auto savingsAccount = new SavingsAccount();
		savingsAccount.increaseBalance(Money(500.00));     // start it off with money

		// amount
		auto amount = Money(30.00);

		scope auto moneyTransfer = new TransferMoneyContext(investmentsAccount, savingsAccount, amount);
		moneyTransfer.doIt();

		writeln("investmentsAccount.availableBalance_ ", investmentsAccount.availableBalance_.val);
	}

	// use case 2
	{
		auto investmentsAccount = new InvestmentAccount();
		investmentsAccount.increaseBalance(Money(100.00));       // prime it with some money

		auto creditor1 = new ElectricCompany();
		auto creditor2 = new GasComponay();
		Array!Creditor creditors = make!(Array!Creditor)();
		creditors.insert(creditor1);
		creditors.insert(creditor2);

		scope auto payBillsContext = new PayBillsContext(investmentsAccount, creditors);
		payBillsContext.doIt();
	}

	writeln("main() done");
}
